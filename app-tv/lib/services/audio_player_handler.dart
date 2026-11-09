import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class VolPiAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static VolPiAudioHandler? _instance;
  static VolPiAudioHandler get instance => _instance!;

  static Future<VolPiAudioHandler> init() async {
    if (_instance != null) return _instance!;
    final handler = await AudioService.init(
      builder: () => VolPiAudioHandler._internal(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.volpi.volpiMedia.audio',
        androidNotificationChannelName: 'VolPi Media Audio Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        notificationColor: Color(0xFF0284C7),
      ),
    );
    _instance = handler;
    return handler;
  }

  final AudioPlayer _player = AudioPlayer();
  int _currentIndex = -1;

  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;

  VolPiAudioHandler._internal() {
    _initStreams();
  }

  void _initStreams() {
    // 1. Broadcast playback state to OS (Lockscreen, Notification, Dynamic Island)
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
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
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          queueIndex: _currentIndex,
        ),
      );
    });

    // 2. Broadcast duration updates
    _player.durationStream.listen((duration) {
      if (duration != null && mediaItem.value != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: duration));
      }
    });

    // 3. Auto-play next track when track completes
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });
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
    final item = queue.value[_currentIndex];
    mediaItem.add(item);

    try {
      await _player.stop();
      await _player.setUrl(item.id);
      await _player.play();
    } catch (e) {
      debugPrint('[VolPiAudioHandler] Error loading track: $e');
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
    if (_currentIndex < queue.value.length - 1) {
      _currentIndex++;
      await _playCurrent();
    } else {
      // Loop or stop
      await _player.seek(Duration.zero);
      await _player.pause();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inSeconds > 3) {
      // Replay current song from start
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

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
