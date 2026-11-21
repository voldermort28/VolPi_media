import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class VolPiAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static VolPiAudioHandler? _instance;
  static bool _isInitialized = false;
  static Future<VolPiAudioHandler>? _initFuture;

  static VolPiAudioHandler get instance => _instance ??= VolPiAudioHandler._internal();

  static Future<VolPiAudioHandler> init() {
    if (_isInitialized && _instance != null) return Future.value(_instance!);
    return _initFuture ??= _doInit();
  }

  static Future<VolPiAudioHandler> _doInit() async {
    final handler = instance;
    // Trên Android / Android TV: dùng trực tiếp just_audio + BaseAudioHandler trong RAM,
    // không gọi AudioService.init để tránh crash ForegroundService / AudioServiceActivity trên Android TV.
    if (!kIsWeb && Platform.isAndroid) {
      _isInitialized = true;
      return handler;
    }
    try {
      await AudioService.init<VolPiAudioHandler>(
        builder: () => handler,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.volpi.volpiMedia.audio',
          androidNotificationChannelName: 'VolPi Media Audio Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          notificationColor: Color(0xFF0284C7),
        ),
      ).timeout(const Duration(seconds: 4));
      _isInitialized = true;
    } catch (e) {
      debugPrint('[VolPiAudioHandler] AudioService.init fallback (local player active): $e');
    }
    return handler;
  }

  AudioPlayer? _playerInstance;
  int _currentIndex = -1;
  int _loadGeneration = 0;
  bool _handledCompletionForCurrentLoad = false;

  final ValueNotifier<bool> shuffleEnabledNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> repeatOneNotifier = ValueNotifier<bool>(false);
  final Random _rng = Random();

  AudioPlayer get _player {
    if (_playerInstance == null) {
      final p = AudioPlayer();
      _playerInstance = p;
      _initStreams(p);
    }
    return _playerInstance!;
  }

  AudioPlayer get player => _player;
  bool get hasActivePlayer => _playerInstance != null;
  int get currentIndex => _currentIndex;
  Stream<double> get volumeStream => _player.volumeStream;
  double get volume => _playerInstance?.volume ?? 1.0;
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  bool get isShuffleEnabled => shuffleEnabledNotifier.value;
  bool get isRepeatOne => repeatOneNotifier.value;

  void toggleShuffle() {
    shuffleEnabledNotifier.value = !shuffleEnabledNotifier.value;
  }

  void toggleRepeatOne() {
    repeatOneNotifier.value = !repeatOneNotifier.value;
  }

  /// Tạm dừng nhạc nền an toàn nếu đang phát (gọi khi mở VideoPlayerScreen)
  Future<void> pauseIfPlaying() async {
    if (_playerInstance != null && _playerInstance!.playing) {
      try {
        await _playerInstance!.pause();
      } catch (_) {}
    }
  }

  VolPiAudioHandler._internal();

  void _initStreams(AudioPlayer audioPlayer) {
    // 1. Broadcast playback state to OS (Lockscreen, Notification, Dynamic Island)
    audioPlayer.playbackEventStream.listen((PlaybackEvent event) {
      final playing = audioPlayer.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[audioPlayer.processingState]!,
          playing: playing,
          updatePosition: audioPlayer.position,
          bufferedPosition: audioPlayer.bufferedPosition,
          speed: audioPlayer.speed,
          queueIndex: _currentIndex,
        ),
      );
    });

    // 2. Broadcast duration updates
    audioPlayer.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    // 2b. Broadcast live buffered position updates (keeping current playback position fresh)
    audioPlayer.bufferedPositionStream.listen((buffered) {
      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: audioPlayer.position,
          bufferedPosition: buffered,
        ),
      );
    });

    // 3. Auto-play next track when track completes (deduplicated per track load)
    audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!_handledCompletionForCurrentLoad) {
          _handledCompletionForCurrentLoad = true;
          if (repeatOneNotifier.value) {
            _replayCurrent();
          } else {
            skipToNext();
          }
        }
      } else if (state.processingState == ProcessingState.ready) {
        _handledCompletionForCurrentLoad = false;
      }
    });
  }

  Future<void> _replayCurrent() async {
    try {
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (e) {
      debugPrint('[VolPiAudioHandler] Replay error: $e');
    }
  }

  /// Sets playlist and starts playing track at index
  Future<void> setPlaylist(List<MediaItem> items, {int initialIndex = 0}) async {
    if (items.isEmpty) return;
    queue.add(items);
    _currentIndex = initialIndex.clamp(0, items.length - 1);
    await _playCurrent();
  }

  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= queue.value.length) return;
    final int gen = ++_loadGeneration;
    _handledCompletionForCurrentLoad = false;
    final item = queue.value[_currentIndex];
    mediaItem.add(item);

    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
        playing: true,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: _currentIndex,
      ),
    );

    try {
      await _player.stop();
      if (gen != _loadGeneration) return;
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(item.id),
          tag: item,
        ),
      );
      if (gen != _loadGeneration) return;
      await _player.play();
    } catch (e) {
      debugPrint('[VolPiAudioHandler] Error loading track: $e');
      if (gen == _loadGeneration) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.idle,
            playing: false,
          ),
        );
      }
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final list = queue.value;
    if (list.isEmpty) return;
    if (shuffleEnabledNotifier.value && list.length > 1) {
      int nextIdx = _rng.nextInt(list.length);
      if (nextIdx == _currentIndex) {
        nextIdx = (_currentIndex + 1) % list.length;
      }
      _currentIndex = nextIdx;
      await _playCurrent();
      return;
    }
    if (_currentIndex < list.length - 1) {
      _currentIndex++;
      await _playCurrent();
    } else {
      await _player.seek(Duration.zero);
      await _player.pause();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      await _playCurrent();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < queue.value.length) {
      _currentIndex = index;
      await _playCurrent();
    }
  }

  /// Dừng hẳn nhạc và ẩn MiniPlayer
  Future<void> stopAndClear() async {
    _loadGeneration++;
    await _playerInstance?.stop();
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _playerInstance?.stop();
    await super.stop();
  }

  void dispose() {
    _playerInstance?.dispose();
  }
}
