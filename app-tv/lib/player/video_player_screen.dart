import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/match_model.dart';
import '../models/watch_history_model.dart';
import '../services/player_settings_service.dart';
import '../services/sync_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/tv_focusable_card.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String subtitle;
  final Map<String, String> headers;
  final List<StreamChannel>? availableChannels;
  final bool isLive;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final Duration? initialPosition;
  final String? mediaId;
  final String? mediaCategory;
  final String? mediaPoster;
  final int episode;
  final int season;

  const VideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.subtitle = '',
    this.headers = const {},
    this.availableChannels,
    this.isLive = false,
    this.onNext,
    this.onPrevious,
    this.initialPosition,
    this.mediaId,
    this.mediaCategory = 'anime',
    this.mediaPoster = '',
    this.episode = 0,
    this.season = 0,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  Timer? _saveProgressTimer;
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _hideControlsTimer;
  late String _currentStreamUrl;
  late String _currentTitle;
  late Map<String, String> _currentHeaders;

  // Swipe Gesture Seeking (Vuốt ngang để tua)
  bool _isDragging = false;
  Duration _dragStartPosition = Duration.zero;
  double _dragTotalDeltaX = 0.0;
  Duration _dragTargetPosition = Duration.zero;
  Timer? _hudFadeTimer;
  String? _hudIcon; // 'FORWARD', 'REWIND'
  String? _hudText;

  // Double-tap Quick Seek Indicators
  bool _showDoubleTapLeft = false;
  bool _showDoubleTapRight = false;
  Timer? _doubleTapTimer;

  // Remote Progressive Seeking (Giữ nút tua nhanh dần trên Android TV)
  bool _isHoldingSeek = false;
  int _holdSeekDirection = 0; // 1: forward, -1: rewind
  DateTime? _holdStartTime;
  int _holdRepeatCount = 0;
  Duration _pendingSeekPosition = Duration.zero;
  Duration _seekAccumulatedDelta = Duration.zero;
  Timer? _commitSeekTimer;
  String? _hudSpeedBadge;

  // Auto-play Next Episode Countdown
  int _nextCountdownSeconds = 0;
  Timer? _nextCountdownTimer;
  bool _hasTriggeredNextCountdown = false;

  // Volume Control (Remembered across clips, streams, episodes and app sessions)
  double _volume = 1.0;
  bool _isMuted = false;
  double _preMuteVolume = 1.0;

  // Mouse Movement & Hover Controls (macOS & Desktop)
  bool _isHoveringControls = false;
  DateTime? _lastMouseMoveTime;
  bool _showStreamSelector = false;

  // TV Remote Focus Nodes
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _seekBarFocusNode = FocusNode();
  final FocusNode _prevFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _replay10FocusNode = FocusNode();
  final FocusNode _forward10FocusNode = FocusNode();
  final FocusNode _skipIntroFocusNode = FocusNode();
  final FocusNode _channelsButtonFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _rotateFocusNode = FocusNode();
  final FocusNode _lockFocusNode = FocusNode();
  final List<FocusNode> _channelFocusNodes = [];

  // Screen Orientation & Touch Lock (Mobile / iOS / Tablet)
  bool _isScreenLocked = false;
  bool _showLockOverlay = false;
  Timer? _lockOverlayTimer;

  List<StreamChannel> get _effectiveChannels {
    if (widget.availableChannels != null && widget.availableChannels!.isNotEmpty) {
      return widget.availableChannels!;
    }
    return [
      StreamChannel(
        name: 'Server 1',
        title: widget.subtitle.isNotEmpty ? widget.subtitle : 'Full HD (Mặc định)',
        url: _currentStreamUrl.isNotEmpty ? _currentStreamUrl : widget.streamUrl,
        headers: widget.headers ?? {},
      ),
    ];
  }

  List<FocusNode> _getActiveControlNodes() {
    final list = <FocusNode>[];
    if (widget.onPrevious != null) list.add(_prevFocusNode);
    if (!widget.isLive) list.add(_replay10FocusNode);
    list.add(_playPauseFocusNode);
    if (!widget.isLive) {
      list.add(_forward10FocusNode);
      list.add(_skipIntroFocusNode);
    }
    if (widget.onNext != null) list.add(_nextFocusNode);
    if (_effectiveChannels.isNotEmpty) list.add(_channelsButtonFocusNode);
    return list;
  }

  void _initChannelFocusNodes() {
    for (final node in _channelFocusNodes) {
      node.dispose();
    }
    _channelFocusNodes.clear();
    final count = _effectiveChannels.length;
    for (int i = 0; i < count; i++) {
      _channelFocusNodes.add(FocusNode());
    }
  }

  void _focusActiveChannel() {
    if (!mounted || !_showStreamSelector || _channelFocusNodes.isEmpty) return;
    int activeIdx = _effectiveChannels.indexWhere((c) => c.url == _currentStreamUrl);
    if (activeIdx < 0 || activeIdx >= _channelFocusNodes.length) activeIdx = 0;
    if (activeIdx < _channelFocusNodes.length) {
      _channelFocusNodes[activeIdx].requestFocus();
    }
  }

  void _handleBackAction() {
    if (_isScreenLocked) {
      setState(() {
        _showLockOverlay = true;
      });
      _startLockOverlayTimer();
      _showBriefPlaybackHud('LOCK', 'Màn hình đang khóa');
      return;
    }
    if (_showStreamSelector) {
      setState(() {
        _showStreamSelector = false;
      });
      _channelsButtonFocusNode.requestFocus();
      _startHideControlsTimer();
      return;
    }
    if (_showControls) {
      setState(() {
        _showControls = false;
      });
      _hideControlsTimer?.cancel();
      return;
    }
    Navigator.of(context).pop();
  }

  bool get _isMacOrDesktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _currentStreamUrl = widget.streamUrl;
    _currentTitle = widget.title;
    _currentHeaders = widget.headers;
    _volume = PlayerSettingsService.instance.volume;
    _isMuted = PlayerSettingsService.instance.isMuted;
    _preMuteVolume = PlayerSettingsService.instance.preMuteVolume;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(_currentStreamUrl),
        httpHeaders: _currentHeaders,
      );

      await _controller.initialize();
      final double targetVol = _isMuted ? 0.0 : _volume;
      await _controller.setVolume(targetVol);
      if (widget.initialPosition != null && widget.initialPosition! > Duration.zero) {
        await _controller.seekTo(widget.initialPosition!);
      }
      await _controller.play();

      // Cố định mức âm lượng đã lưu sau khi luồng phát bắt đầu để ngăn native AVPlayer/ExoPlayer tự ý bật lại 100%
      await _controller.setVolume(targetVol);
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && _isInitialized) {
          _controller.setVolume(_isMuted ? 0.0 : _volume);
        }
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _isInitialized) {
          _controller.setVolume(_isMuted ? 0.0 : _volume);
        }
      });

      _controller.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _startHideControlsTimer();
        _saveProgressTimer?.cancel();
        _saveProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          _saveCurrentProgress();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Không thể phát luồng này: ${e.toString()}';
        });
      }
    }
  }

  void _videoListener() {
    if (!mounted || !_isInitialized) return;

    // Check auto-play next episode when near end (last 15 seconds) or ended
    if (widget.onNext != null && !widget.isLive && !_hasTriggeredNextCountdown) {
      final pos = _controller.value.position;
      final dur = _controller.value.duration;
      if (dur > const Duration(seconds: 30) && (pos >= dur - const Duration(seconds: 15) || (!dur.isNegative && pos >= dur && dur > Duration.zero))) {
        _startNextEpisodeCountdown();
      }
    }

    // Performance optimization for low-end hardware:
    // Only rebuild UI if controls or countdown are currently visible.
    if (_showControls || _nextCountdownSeconds > 0) {
      setState(() {});
    }
  }

  void _startNextEpisodeCountdown() {
    if (_hasTriggeredNextCountdown || widget.onNext == null) return;
    _hasTriggeredNextCountdown = true;
    _nextCountdownSeconds = 8;
    _nextCountdownTimer?.cancel();
    _nextCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_nextCountdownSeconds <= 1) {
        timer.cancel();
        _playNextEpisodeImmediately();
      } else {
        setState(() {
          _nextCountdownSeconds--;
        });
      }
    });
    setState(() {});
  }

  void _playNextEpisodeImmediately() {
    _nextCountdownTimer?.cancel();
    _nextCountdownTimer = null;
    setState(() {
      _nextCountdownSeconds = 0;
    });
    widget.onNext?.call();
  }

  void _cancelNextCountdown() {
    setState(() {
      _nextCountdownTimer?.cancel();
      _nextCountdownTimer = null;
      _nextCountdownSeconds = 0;
    });
  }

  void _seekDirectOffset(int seconds, {String? customHudText}) {
    if (!_isInitialized || widget.isLive) return;
    final currentPos = _controller.value.position;
    final totalDuration = _controller.value.duration;
    final targetSeconds = (currentPos.inSeconds + seconds).clamp(0, totalDuration.inSeconds);
    final target = Duration(seconds: targetSeconds);
    _controller.seekTo(target);
    _hudFadeTimer?.cancel();
    setState(() {
      _hudIcon = seconds >= 0 ? 'FORWARD' : 'REWIND';
      _hudText = customHudText ?? '${seconds >= 0 ? '+' : ''}${seconds}s';
    });
    _hudFadeTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
        });
      }
    });
    _showControlsBriefly();
  }

  void _setVolume(double newVol) {
    // Làm tròn chính xác 2 chữ số thập phân để tránh sai số dấu phẩy động (vd: 0.0499999999)
    final rounded = (newVol * 100).round() / 100.0;
    final clamped = rounded.clamp(0.0, 1.0);
    setState(() {
      _volume = clamped;
      _isMuted = clamped == 0.0;
    });
    PlayerSettingsService.instance.saveVolume(
      volume: _volume,
      isMuted: _isMuted,
      preMuteVolume: _preMuteVolume,
    );
    if (_isInitialized) {
      _controller.setVolume(_isMuted ? 0.0 : _volume);
    }
    _showVolumeHud(clamped);
    _showControlsBriefly();
  }

  void _toggleMute() {
    if (_isMuted) {
      _setVolume(_preMuteVolume > 0.0 ? _preMuteVolume : 1.0);
    } else {
      _preMuteVolume = _volume > 0.0 ? _volume : 1.0;
      PlayerSettingsService.instance.saveVolume(
        volume: _volume,
        isMuted: true,
        preMuteVolume: _preMuteVolume,
      );
      _setVolume(0.0);
    }
  }

  /// Tinh chỉnh âm lượng khi cuộn chuột:
  /// - Khi giữ phím Shift: Vi chỉnh chính xác từng 1% ở mọi mức âm lượng
  /// - Khi cuộn thông thường:
  ///   + Mức > 5%: Tăng/giảm nhanh mỗi nấc 5%
  ///   + Mức <= 5%: Tự động chuyển sang nấc 1% (cho phép chỉnh về 4%, 3%, 2%, 1% và không bị tắt phụt âm thanh)
  void _adjustVolumeScroll(bool isScrollUp, {bool isFineTune = false}) {
    final double current = _isMuted ? 0.0 : _volume;
    int currentPercent = (current * 100).round();

    int stepPercent;
    if (isFineTune) {
      // Giữ phím Shift: vi chỉnh chính xác từng 1%
      stepPercent = 1;
    } else if (isScrollUp) {
      // Khi tăng từ dưới 5%: tăng từng 1% (0% -> 1% -> 2% -> 3% -> 4% -> 5%)
      // Khi từ 5% trở lên: tăng 5%
      stepPercent = currentPercent < 5 ? 1 : 5;
    } else {
      // Khi giảm: nếu đang <= 5%, giảm từng 1% (5% -> 4% -> 3% -> 2% -> 1% -> 0%)
      // Nếu đang > 5%, giảm 5%
      stepPercent = currentPercent <= 5 ? 1 : 5;
    }

    int targetPercent = isScrollUp ? (currentPercent + stepPercent) : (currentPercent - stepPercent);

    // Khi cuộn thông thường giảm từ mức lớn, căn chỉnh về bội số của 5% (vd: từ 7% -> 5%)
    if (!isFineTune && !isScrollUp && targetPercent > 5 && targetPercent % 5 != 0) {
      targetPercent = (targetPercent ~/ 5) * 5;
    }

    targetPercent = targetPercent.clamp(0, 100);
    _setVolume(targetPercent / 100.0);
  }

  void _changeVolumeBy(double delta) {
    final target = (_isMuted ? 0.0 : _volume) + delta;
    _setVolume(target);
  }

  void _showVolumeHud(double vol) {
    _hudFadeTimer?.cancel();
    setState(() {
      _hudIcon = vol == 0.0 ? 'VOLUME_MUTE' : (vol < 0.5 ? 'VOLUME_LOW' : 'VOLUME_HIGH');
      _hudText = vol == 0.0 ? 'Tắt tiếng' : '${(vol * 100).round()}%';
      _hudSpeedBadge = 'Âm lượng';
    });
    _showControlsBriefly();
    _hudFadeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
          _hudSpeedBadge = null;
        });
      }
    });
  }

  void _showBriefPlaybackHud(String icon, String text) {
    _hudFadeTimer?.cancel();
    setState(() {
      _hudIcon = icon;
      _hudText = text;
      _hudSpeedBadge = null;
    });
    _showControlsBriefly();
    _hudFadeTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted && _hudIcon == icon) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
          _hudSpeedBadge = null;
        });
      }
    });
  }

  void _switchChannel(StreamChannel channel) {
    if (_currentStreamUrl == channel.url && !_hasError) return;
    try {
      _controller.removeListener(_videoListener);
      _controller.dispose();
    } catch (_) {}
    setState(() {
      _currentStreamUrl = channel.url;
      _currentTitle = channel.title;
      _currentHeaders = channel.headers;
    });
    _initPlayer();
  }

  void _switchChannelDelta(int delta) {
    final channels = _effectiveChannels;
    if (channels.length <= 1) return;
    int currentIndex = channels.indexWhere((c) => c.url == _currentStreamUrl);
    if (currentIndex == -1) currentIndex = 0;

    int newIndex = currentIndex + delta;
    if (newIndex < 0) {
      newIndex = channels.length - 1;
    } else if (newIndex >= channels.length) {
      newIndex = 0;
    }

    final targetChannel = channels[newIndex];
    _switchChannel(targetChannel);

    _hudFadeTimer?.cancel();
    setState(() {
      _hudIcon = 'CHANNEL';
      _hudText = targetChannel.title;
      _hudSpeedBadge = '${newIndex + 1}/${channels.length}';
    });

    _hudFadeTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
          _hudSpeedBadge = null;
        });
      }
    });

    _showControlsBriefly();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _controller.value.isPlaying && !_isDragging && !_isHoldingSeek && !_isHoveringControls) {
        setState(() {
          _showControls = false;
          _showStreamSelector = false;
        });
      }
    });
  }

  void _toggleScreenOrientation() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      _showBriefPlaybackHud('ROTATE', 'Màn hình dọc');
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _showBriefPlaybackHud('ROTATE', 'Màn hình ngang');
    }
  }

  void _toggleLockScreen() {
    setState(() {
      _isScreenLocked = !_isScreenLocked;
      if (_isScreenLocked) {
        _showControls = false;
        _showLockOverlay = true;
      } else {
        _showControls = true;
      }
    });
    if (_isScreenLocked) {
      _showBriefPlaybackHud('LOCK', 'Đã khóa màn hình cảm ứng');
      _startLockOverlayTimer();
    } else {
      _showBriefPlaybackHud('UNLOCK', 'Đã mở khóa màn hình');
      _startHideControlsTimer();
    }
  }

  void _startLockOverlayTimer() {
    _lockOverlayTimer?.cancel();
    _lockOverlayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isScreenLocked) {
        setState(() {
          _showLockOverlay = false;
        });
      }
    });
  }

  void _onMouseMove() {
    if (!_isMacOrDesktop || _isScreenLocked) return;
    final now = DateTime.now();
    if (_lastMouseMoveTime != null && now.difference(_lastMouseMoveTime!).inMilliseconds < 80) {
      return;
    }
    _lastMouseMoveTime = now;

    if (!_showControls) {
      setState(() {
        _showControls = true;
      });
    }
    _startHideControlsTimer();
  }

  void _showControlsBriefly() {
    if (_isScreenLocked) return;
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anyFocused = _getActiveControlNodes().any((n) => n.hasFocus) ||
          _seekBarFocusNode.hasFocus ||
          _backButtonFocusNode.hasFocus;
      if (mounted && _showControls && !anyFocused) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  void _toggleControls() {
    if (_isScreenLocked) return;
    if (_showStreamSelector) {
      setState(() {
        _showStreamSelector = false;
        _showControls = false;
      });
      _hideControlsTimer?.cancel();
      return;
    }
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final anyFocused = _getActiveControlNodes().any((n) => n.hasFocus) ||
            _seekBarFocusNode.hasFocus ||
            _backButtonFocusNode.hasFocus;
        if (mounted && _showControls && !anyFocused) {
          _playPauseFocusNode.requestFocus();
        }
      });
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _playVideo() {
    if (!_isInitialized) return;
    if (!_controller.value.isPlaying) {
      _controller.play();
    }
    _showBriefPlaybackHud('PLAY', 'Đang phát');
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _pauseVideo() {
    if (!_isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    }
    _showBriefPlaybackHud('PAUSE', 'Tạm dừng');
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer?.cancel();
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    if (_controller.value.isPlaying) {
      _pauseVideo();
    } else {
      _playVideo();
    }
  }

  String _getActiveChannelTitleShort() {
    final channels = _effectiveChannels;
    if (channels.isEmpty) {
      return 'Chọn Luồng';
    }
    final current = channels.firstWhere(
      (c) => c.url == _currentStreamUrl,
      orElse: () => channels.first,
    );
    final title = current.title;
    final match = RegExp(r'(Server\s*#?\d+|Luồng\s*#?\d+|TM\s*#?\d+|R2|CDN|Thuyết Minh|Lồng Tiếng|Phụ Đề)', caseSensitive: false).firstMatch(title);
    if (match != null) {
      return match.group(0)!;
    }
    return title.length > 12 ? '${title.substring(0, 10)}...' : title;
  }

  String _formatDuration(Duration d) {
    final int totalSeconds = d.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDelta(Duration d, int direction) {
    final int totalSec = d.inSeconds.abs();
    final String sign = direction >= 0 ? '+' : '-';
    if (totalSec < 60) {
      return '$sign${totalSec}s';
    }
    final int minutes = totalSec ~/ 60;
    final int seconds = totalSec % 60;
    if (seconds == 0) {
      return '$sign${minutes}m';
    }
    return '$sign${minutes}m ${seconds}s';
  }

  void _seekRelative(int seconds) {
    if (!_isInitialized || widget.isLive) return;
    final dir = seconds >= 0 ? 1 : -1;
    _handleRemoteSeekStart(dir);
  }

  void _handleRemoteSeekStart(int direction) {
    if (!_isInitialized || widget.isLive) return;

    final now = DateTime.now();

    if (!_isHoldingSeek || _holdSeekDirection != direction) {
      _isHoldingSeek = true;
      _holdSeekDirection = direction;
      _holdStartTime = now;
      _holdRepeatCount = 0;
      _pendingSeekPosition = _controller.value.position;
      _seekAccumulatedDelta = Duration.zero;
    }

    _applySeekStep(direction, 10, '1x');
  }

  void _handleRemoteSeekRepeat(int direction) {
    if (!_isInitialized || widget.isLive) return;

    if (!_isHoldingSeek || _holdSeekDirection != direction) {
      _handleRemoteSeekStart(direction);
      return;
    }

    _holdRepeatCount++;
    final elapsedMs = _holdStartTime != null
        ? DateTime.now().difference(_holdStartTime!).inMilliseconds
        : 0;

    int stepSeconds;
    String speedBadge;

    if (elapsedMs > 5500 || _holdRepeatCount > 40) {
      stepSeconds = 180; // 3m per tick
      speedBadge = '16x';
    } else if (elapsedMs > 3500 || _holdRepeatCount > 25) {
      stepSeconds = 90; // 1.5m per tick
      speedBadge = '8x';
    } else if (elapsedMs > 2000 || _holdRepeatCount > 15) {
      stepSeconds = 45; // 45s per tick
      speedBadge = '4x';
    } else if (elapsedMs > 800 || _holdRepeatCount > 6) {
      stepSeconds = 20; // 20s per tick
      speedBadge = '2x';
    } else {
      stepSeconds = 10; // 10s per tick
      speedBadge = '1x';
    }

    _applySeekStep(direction, stepSeconds, speedBadge);
  }

  void _applySeekStep(int direction, int stepSeconds, String speedBadge) {
    final duration = _controller.value.duration;
    final step = Duration(seconds: stepSeconds * direction);

    _seekAccumulatedDelta += step;
    final newPos = _pendingSeekPosition + step;
    _pendingSeekPosition = newPos < Duration.zero
        ? Duration.zero
        : (newPos > duration ? duration : newPos);

    _hudFadeTimer?.cancel();
    setState(() {
      _hudIcon = direction > 0 ? 'FORWARD' : 'REWIND';
      _hudText = _formatDelta(_seekAccumulatedDelta, direction);
      _hudSpeedBadge = speedBadge;
      _dragTargetPosition = _pendingSeekPosition;
    });

    _showControlsBriefly();

    // Auto-commit if no key events arrive within 400ms
    _commitSeekTimer?.cancel();
    _commitSeekTimer = Timer(const Duration(milliseconds: 400), () {
      _commitPendingSeek();
    });
  }

  void _handleRemoteSeekEnd(int direction) {
    if (_isHoldingSeek && _holdSeekDirection == direction) {
      _commitPendingSeek();
    }
  }

  void _commitPendingSeek() {
    _commitSeekTimer?.cancel();
    if (!_isHoldingSeek || !_isInitialized || widget.isLive) {
      _isHoldingSeek = false;
      return;
    }

    final target = _pendingSeekPosition;
    _isHoldingSeek = false;
    _holdRepeatCount = 0;
    _holdStartTime = null;

    _controller.seekTo(target);

    _hudFadeTimer?.cancel();
    _hudFadeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isHoldingSeek && (_hudIcon == 'FORWARD' || _hudIcon == 'REWIND')) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
          _hudSpeedBadge = null;
        });
      }
    });

    _showControlsBriefly();
  }

  // --- Touch Gestures Handling ---
  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_isInitialized || widget.isLive) return;
    _dragStartPosition = _controller.value.position;
    _dragTotalDeltaX = 0.0;
    _isDragging = true;
    _hudFadeTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isInitialized || widget.isLive || !_isDragging) return;
    _dragTotalDeltaX += details.primaryDelta ?? 0.0;

    // 1px drag = ~0.4s seek
    final deltaSeconds = (_dragTotalDeltaX * 0.4).toInt();
    final duration = _controller.value.duration;
    final targetSeconds = (_dragStartPosition.inSeconds + deltaSeconds).clamp(0, duration.inSeconds);
    final target = Duration(seconds: targetSeconds);

    setState(() {
      _dragTargetPosition = target;
      _hudIcon = deltaSeconds >= 0 ? 'FORWARD' : 'REWIND';
      final sign = deltaSeconds >= 0 ? '+' : '';
      _hudText = '$sign${deltaSeconds}s';
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isInitialized || widget.isLive || !_isDragging) return;
    _isDragging = false;
    _controller.seekTo(_dragTargetPosition);

    _hudFadeTimer?.cancel();
    _hudFadeTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
        });
      }
    });
    _showControlsBriefly();
  }

  void _onDoubleTapSide(bool isRight) {
    if (!_isInitialized || widget.isLive) return;
    if (isRight) {
      _seekRelative(10);
      _doubleTapTimer?.cancel();
      setState(() {
        _showDoubleTapRight = true;
        _showDoubleTapLeft = false;
      });
    } else {
      _seekRelative(-10);
      _doubleTapTimer?.cancel();
      setState(() {
        _showDoubleTapLeft = true;
        _showDoubleTapRight = false;
      });
    }
    _doubleTapTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _showDoubleTapLeft = false;
          _showDoubleTapRight = false;
        });
      }
    });
  }

  void _saveCurrentProgress() {
    if (!mounted || !_isInitialized || widget.isLive || widget.mediaId == null || widget.mediaId!.isEmpty) return;
    try {
      final pos = _controller.value.position;
      final dur = _controller.value.duration;
      if (pos.inMilliseconds < 1000 || dur.inMilliseconds < 1000) return;

      WatchHistoryService.instance.saveProgress(
        WatchHistoryItem(
          id: widget.mediaId!,
          mediaId: widget.mediaId!,
          title: widget.title,
          subtitle: widget.subtitle,
          poster: widget.mediaPoster ?? '',
          streamUrl: _currentStreamUrl,
          positionMs: pos.inMilliseconds,
          durationMs: dur.inMilliseconds,
          category: widget.mediaCategory ?? 'anime',
          episode: widget.episode,
          season: widget.season,
          updatedAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveProgressTimer?.cancel();
    _saveCurrentProgress();
    WatchHistoryService.instance.flush();
    SyncService.pushToServer(null);
    _hideControlsTimer?.cancel();
    _lockOverlayTimer?.cancel();
    _nextCountdownTimer?.cancel();
    _hudFadeTimer?.cancel();
    _doubleTapTimer?.cancel();
    _commitSeekTimer?.cancel();
    _controller.removeListener(_videoListener);
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _playPauseFocusNode.dispose();
    _seekBarFocusNode.dispose();
    _prevFocusNode.dispose();
    _nextFocusNode.dispose();
    _replay10FocusNode.dispose();
    _forward10FocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _channelsButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _rotateFocusNode.dispose();
    _lockFocusNode.dispose();
    for (final n in _channelFocusNodes) {
      n.dispose();
    }
    _channelFocusNodes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleBackAction();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final key = event.logicalKey;
          final int code = key.keyId & 0xFFFF;
          final String debugName = key.debugName?.toLowerCase() ?? '';

          // 1. Physical Play key on remote
          final bool isPlayKey = key == LogicalKeyboardKey.mediaPlay ||
              code == 126 ||
              (debugName.contains('mediaplay') && !debugName.contains('pause'));

          // 2. Physical Pause / Stop key on remote
          final bool isPauseKey = key == LogicalKeyboardKey.mediaPause ||
              key == LogicalKeyboardKey.mediaStop ||
              code == 127 ||
              code == 86 ||
              ((debugName.contains('mediapause') || debugName.contains('mediastop')) && !debugName.contains('play'));

          // 3. Play / Pause toggle key (Space, mediaPlayPause, or desktop Key K)
          final bool isPlayPauseToggle = key == LogicalKeyboardKey.mediaPlayPause ||
              key == LogicalKeyboardKey.space ||
              code == 85 ||
              debugName.contains('playpause') ||
              debugName.contains('play_pause') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyK);

          // 4. Physical Fast Forward (Tua tới) key on remote
          final bool isFwdKey = key == LogicalKeyboardKey.mediaFastForward ||
              key == LogicalKeyboardKey.mediaSkipForward ||
              key == LogicalKeyboardKey.mediaStepForward ||
              code == 90 ||
              code == 272 ||
              code == 274 ||
              debugName.contains('fastforward') ||
              debugName.contains('fast_forward') ||
              debugName.contains('skipforward') ||
              debugName.contains('skip_forward') ||
              debugName.contains('stepforward') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyL);

          // 5. Physical Rewind (Tua lui) key on remote
          final bool isRwdKey = key == LogicalKeyboardKey.mediaRewind ||
              key == LogicalKeyboardKey.mediaSkipBackward ||
              key == LogicalKeyboardKey.mediaStepBackward ||
              code == 89 ||
              code == 273 ||
              code == 275 ||
              debugName.contains('rewind') ||
              debugName.contains('skipbackward') ||
              debugName.contains('skip_backward') ||
              debugName.contains('stepbackward') ||
              debugName.contains('step_backward') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyJ);

          // 6. Track navigation (Previous / Next Track)
          final bool isPrevTrack = key == LogicalKeyboardKey.mediaTrackPrevious ||
              code == 88 ||
              debugName.contains('trackprevious') ||
              debugName.contains('track_previous') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyP);
          final bool isNextTrack = key == LogicalKeyboardKey.mediaTrackNext ||
              code == 87 ||
              debugName.contains('tracknext') ||
              debugName.contains('track_next') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyN);

          // 7. D-pad Navigation Left / Right
          final bool isLeft = key == LogicalKeyboardKey.arrowLeft;
          final bool isRight = key == LogicalKeyboardKey.arrowRight;

          final bool isBack = key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.backspace;

          if (event is KeyDownEvent) {
            if (isBack) {
              _handleBackAction();
              return KeyEventResult.handled;
            }

            if (_isScreenLocked) {
              return KeyEventResult.ignored;
            }

            // Dedicated Remote Play Key
            if (isPlayKey) {
              _playVideo();
              return KeyEventResult.handled;
            }

            // Dedicated Remote Pause Key
            if (isPauseKey) {
              _pauseVideo();
              return KeyEventResult.handled;
            }

            // Dedicated Remote Play/Pause Toggle Key
            if (isPlayPauseToggle) {
              _togglePlayPause();
              return KeyEventResult.handled;
            }

            // Dedicated Remote Fast Forward (Tua tới) Key
            if (isFwdKey) {
              if (widget.isLive) {
                _showBriefPlaybackHud('CHANNEL', 'Đang phát trực tiếp');
                return KeyEventResult.handled;
              }
              if (_showStreamSelector) {
                setState(() {
                  _showStreamSelector = false;
                });
              }
              if (_isHoldingSeek && _holdSeekDirection == 1) {
                _handleRemoteSeekRepeat(1);
              } else {
                _handleRemoteSeekStart(1);
              }
              return KeyEventResult.handled;
            }

            // Dedicated Remote Rewind (Tua lui) Key
            if (isRwdKey) {
              if (widget.isLive) {
                _showBriefPlaybackHud('CHANNEL', 'Đang phát trực tiếp');
                return KeyEventResult.handled;
              }
              if (_showStreamSelector) {
                setState(() {
                  _showStreamSelector = false;
                });
              }
              if (_isHoldingSeek && _holdSeekDirection == -1) {
                _handleRemoteSeekRepeat(-1);
              } else {
                _handleRemoteSeekStart(-1);
              }
              return KeyEventResult.handled;
            }

            if (isPrevTrack && widget.onPrevious != null) {
              widget.onPrevious!();
              return KeyEventResult.handled;
            }
            if (isNextTrack && widget.onNext != null) {
              widget.onNext!();
              return KeyEventResult.handled;
            }

            // Select / Enter
            if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
              if (!_showControls) {
                _showControlsBriefly();
                return KeyEventResult.handled;
              }
              // When controls are visible, let the focused TvFocusableCard button handle Enter!
              return KeyEventResult.ignored;
            }

            // Left navigation / seek
            if (isLeft) {
              if (_lockFocusNode.hasFocus) {
                _rotateFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (_rotateFocusNode.hasFocus) {
                _backButtonFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (!_showControls) {
                if (_isHoldingSeek && _holdSeekDirection == -1) {
                  _handleRemoteSeekRepeat(-1);
                } else {
                  _handleRemoteSeekStart(-1);
                }
                return KeyEventResult.handled;
              }
              if (_seekBarFocusNode.hasFocus) {
                if (_isHoldingSeek && _holdSeekDirection == -1) {
                  _handleRemoteSeekRepeat(-1);
                } else {
                  _handleRemoteSeekStart(-1);
                }
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // Explicitly navigate between control buttons in the bottom bar
              final controlNodes = _getActiveControlNodes();
              final currentIdx = controlNodes.indexWhere((n) => n.hasFocus);
              if (currentIdx > 0) {
                controlNodes[currentIdx - 1].requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              _startHideControlsTimer();
              return KeyEventResult.ignored;
            }

            // Right navigation / seek
            if (isRight) {
              if (_backButtonFocusNode.hasFocus) {
                _rotateFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (_rotateFocusNode.hasFocus) {
                _lockFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (!_showControls) {
                if (_isHoldingSeek && _holdSeekDirection == 1) {
                  _handleRemoteSeekRepeat(1);
                } else {
                  _handleRemoteSeekStart(1);
                }
                return KeyEventResult.handled;
              }
              if (_seekBarFocusNode.hasFocus) {
                if (_isHoldingSeek && _holdSeekDirection == 1) {
                  _handleRemoteSeekRepeat(1);
                } else {
                  _handleRemoteSeekStart(1);
                }
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // Explicitly navigate between control buttons in the bottom bar
              final controlNodes = _getActiveControlNodes();
              final currentIdx = controlNodes.indexWhere((n) => n.hasFocus);
              if (currentIdx != -1 && currentIdx + 1 < controlNodes.length) {
                controlNodes[currentIdx + 1].requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              _startHideControlsTimer();
              return KeyEventResult.ignored;
            }

            // Volume Shortcuts for macOS & Desktop (Key M for mute, +/- for volume)
            if (_isMacOrDesktop) {
              if (key == LogicalKeyboardKey.keyM) {
                _toggleMute();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.equal ||
                  key == LogicalKeyboardKey.numpadAdd) {
                _changeVolumeBy(0.05);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.minus ||
                  key == LogicalKeyboardKey.numpadSubtract) {
                _changeVolumeBy(-0.05);
                return KeyEventResult.handled;
              }
            }

            final bool isUp = key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.channelUp ||
                key == LogicalKeyboardKey.pageUp;
            final bool isDown = key == LogicalKeyboardKey.arrowDown ||
                key == LogicalKeyboardKey.channelDown ||
                key == LogicalKeyboardKey.pageDown;

            if (isUp) {
              if (!_showControls) {
                _showControlsBriefly();
                return KeyEventResult.handled;
              }
              if (_showStreamSelector) {
                _startHideControlsTimer();
                return KeyEventResult.ignored;
              }
              if (_seekBarFocusNode.hasFocus) {
                _backButtonFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (_backButtonFocusNode.hasFocus || _rotateFocusNode.hasFocus || _lockFocusNode.hasFocus) {
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // For Live (Football), there is no seekbar -> Up goes directly to back button
              if (widget.isLive) {
                _backButtonFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              _seekBarFocusNode.requestFocus();
              _startHideControlsTimer();
              return KeyEventResult.handled;
            }
            if (isDown) {
              if (!_showControls) {
                _showControlsBriefly();
                return KeyEventResult.handled;
              }
              if (_showStreamSelector) {
                _startHideControlsTimer();
                return KeyEventResult.ignored;
              }
              if (_backButtonFocusNode.hasFocus || _rotateFocusNode.hasFocus || _lockFocusNode.hasFocus) {
                if (widget.isLive) {
                  _playPauseFocusNode.requestFocus();
                } else {
                  _seekBarFocusNode.requestFocus();
                }
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (_seekBarFocusNode.hasFocus) {
                _playPauseFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // From bottom control buttons -> Down to dismiss controls!
              setState(() {
                _showControls = false;
              });
              _hideControlsTimer?.cancel();
              return KeyEventResult.handled;
            }
          } else if (event is KeyRepeatEvent) {
            if (_isScreenLocked) return KeyEventResult.ignored;
            if (isPlayKey || isPauseKey || isPlayPauseToggle) {
              return KeyEventResult.handled;
            }
            if (isFwdKey) {
              if (!widget.isLive) _handleRemoteSeekRepeat(1);
              return KeyEventResult.handled;
            }
            if (isRwdKey) {
              if (!widget.isLive) _handleRemoteSeekRepeat(-1);
              return KeyEventResult.handled;
            }
            if (isLeft && (!_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekRepeat(-1);
              return KeyEventResult.handled;
            }
            if (isRight && (!_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekRepeat(1);
              return KeyEventResult.handled;
            }
          } else if (event is KeyUpEvent) {
            if (_isScreenLocked) return KeyEventResult.ignored;
            if (isPlayKey || isPauseKey || isPlayPauseToggle) {
              return KeyEventResult.handled;
            }
            if (isFwdKey) {
              if (!widget.isLive) _handleRemoteSeekEnd(1);
              return KeyEventResult.handled;
            }
            if (isRwdKey) {
              if (!widget.isLive) _handleRemoteSeekEnd(-1);
              return KeyEventResult.handled;
            }
            if (isLeft && (!_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekEnd(-1);
              return KeyEventResult.handled;
            }
            if (isRight && (!_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekEnd(1);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          cursor: (_isMacOrDesktop && !_showControls) ? SystemMouseCursors.none : SystemMouseCursors.basic,
          onHover: (_) => _onMouseMove(),
          onEnter: (_) => _onMouseMove(),
          child: Listener(
            onPointerHover: (_) {
              if (_isMacOrDesktop) _onMouseMove();
            },
            onPointerMove: (_) {
              if (_isMacOrDesktop) _onMouseMove();
            },
            onPointerSignal: (pointerSignal) {
              if (_isMacOrDesktop && pointerSignal is PointerScrollEvent) {
                final bool isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
                if (pointerSignal.scrollDelta.dy < 0) {
                  _adjustVolumeScroll(true, isFineTune: isShiftPressed);
                } else if (pointerSignal.scrollDelta.dy > 0) {
                  _adjustVolumeScroll(false, isFineTune: isShiftPressed);
                }
              }
            },
            child: GestureDetector(
              onTap: () {
                if (_isScreenLocked) {
                  setState(() {
                    _showLockOverlay = true;
                  });
                  _startLockOverlayTimer();
                  return;
                }
                _toggleControls();
              },
              onHorizontalDragStart: _isScreenLocked ? null : _onHorizontalDragStart,
              onHorizontalDragUpdate: _isScreenLocked ? null : _onHorizontalDragUpdate,
              onHorizontalDragEnd: _isScreenLocked ? null : _onHorizontalDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. VIDEO CANVAS
              if (_isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16 / 9,
                    child: VideoPlayer(_controller),
                  ),
                )
              else if (_hasError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'Lỗi phát video',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _errorMessage,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        if (_effectiveChannels.length > 1) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Chọn luồng phát khác để xem:',
                            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: _effectiveChannels.map((ch) {
                              final bool isCurrent = ch.url == _currentStreamUrl;
                              return TvFocusableCard(
                                onTap: () => _switchChannel(ch),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isCurrent ? const Color(0xFFEF4444).withOpacity(0.3) : const Color(0xFF334155),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isCurrent ? Colors.redAccent : Colors.white24,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.play_circle_outline,
                                        color: isCurrent ? Colors.redAccent : const Color(0xFF38BDF8),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        ch.title,
                                        style: TextStyle(
                                          color: isCurrent ? Colors.white70 : Colors.white,
                                          fontSize: 12,
                                          fontWeight: isCurrent ? FontWeight.normal : FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 20),
                        TvFocusableCard(
                          onTap: _initPlayer,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            color: const Color(0xFF38BDF8),
                            child: const Text('Thử lại', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF38BDF8)),
                      SizedBox(height: 16),
                      Text('Đang tải luồng phát...', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),

              // 2. DOUBLE-TAP SEEK ZONES (Left 35% & Right 35%)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: screenSize.width * 0.35,
                child: GestureDetector(
                  onDoubleTap: () {
                    if (_isScreenLocked) return;
                    _onDoubleTapSide(false);
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: screenSize.width * 0.35,
                child: GestureDetector(
                  onDoubleTap: () {
                    if (_isScreenLocked) return;
                    _onDoubleTapSide(true);
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Container(),
                ),
              ),

              // 3. DOUBLE-TAP RIPPLE INDICATORS
              if (_showDoubleTapLeft)
                Positioned(
                  left: screenSize.width * 0.15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.replay_10_rounded, color: Color(0xFF38BDF8), size: 36),
                        SizedBox(width: 8),
                        Text('-10s', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              if (_showDoubleTapRight)
                Positioned(
                  right: screenSize.width * 0.15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('+10s', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(width: 8),
                        Icon(Icons.forward_10_rounded, color: Color(0xFF38BDF8), size: 36),
                      ],
                    ),
                  ),
                ),

              // 4. OSD OVERLAY CONTROLS (Top Bar, Bottom Timeline & Controls Below Progress Bar)
              ExcludeFocus(
                excluding: !_showControls || _isScreenLocked,
                child: AnimatedOpacity(
                  opacity: (_showControls && !_isScreenLocked) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_showControls || _isScreenLocked,
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Bar with localized gentle gradient (No full-screen darkening)
                          MouseRegion(
                            onEnter: (_) {
                              _isHoveringControls = true;
                              _hideControlsTimer?.cancel();
                            },
                            onExit: (_) {
                              _isHoveringControls = false;
                              _startHideControlsTimer();
                            },
                            child: Container(
                              decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withOpacity(0.65),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              children: [
                                TvFocusableCard(
                                  focusNode: _backButtonFocusNode,
                                  onTap: _handleBackAction,
                                  scale: 1.1,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                                  ),
                                ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _currentTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        shadows: [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1))],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (widget.subtitle.isNotEmpty)
                                      Text(
                                        widget.subtitle,
                                        style: const TextStyle(
                                          color: Color(0xFF38BDF8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (widget.isLive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text('TRỰC TIẾP', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              // HUD Status Pill (Bên trên video, cạnh phần volume, không đụng tiêu đề phim)
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(begin: 0.85, end: 1.0).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: _hudIcon != null
                                    ? Container(
                                        key: ValueKey('hud_${_hudIcon}_${_hudText}'),
                                        margin: const EdgeInsets.only(left: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xE60F172A),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF38BDF8).withOpacity(0.25),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _hudIcon == 'PLAY'
                                                  ? Icons.play_arrow_rounded
                                                  : (_hudIcon == 'PAUSE'
                                                      ? Icons.pause_rounded
                                                      : (_hudIcon == 'CHANNEL'
                                                          ? Icons.live_tv_rounded
                                                          : (_hudIcon == 'FORWARD'
                                                              ? Icons.fast_forward_rounded
                                                              : (_hudIcon == 'REWIND'
                                                                  ? Icons.fast_rewind_rounded
                                                                  : (_hudIcon == 'VOLUME_MUTE'
                                                                      ? Icons.volume_off_rounded
                                                                      : (_hudIcon == 'VOLUME_LOW'
                                                                          ? Icons.volume_down_rounded
                                                                          : (_hudIcon == 'LOCK'
                                                                              ? Icons.lock_rounded
                                                                              : (_hudIcon == 'UNLOCK'
                                                                                  ? Icons.lock_open_rounded
                                                                                  : (_hudIcon == 'ROTATE'
                                                                                      ? Icons.screen_rotation_rounded
                                                                                      : Icons.volume_up_rounded))))))))),
                                              color: const Color(0xFF38BDF8),
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _hudText ?? '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                            if (_hudSpeedBadge != null) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF0284C7),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                                                ),
                                                child: Text(
                                                  _hudSpeedBadge!,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              // Rotate Screen Button
                              const SizedBox(width: 8),
                              TvFocusableCard(
                                focusNode: _rotateFocusNode,
                                onTap: _toggleScreenOrientation,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24, width: 0.8),
                                  ),
                                  child: const Icon(
                                    Icons.screen_rotation_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                              // Lock Touch Screen Button
                              const SizedBox(width: 8),
                              TvFocusableCard(
                                focusNode: _lockFocusNode,
                                onTap: _toggleLockScreen,
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24, width: 0.8),
                                  ),
                                  child: const Icon(
                                    Icons.lock_outline_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                              if (_isMacOrDesktop) ...[
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white24, width: 0.8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TvFocusableCard(
                                        onTap: _toggleMute,
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          child: Icon(
                                            _isMuted || _volume == 0.0
                                                ? Icons.volume_off_rounded
                                                : (_volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                                            color: _isMuted ? Colors.redAccent : Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 75,
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            activeTrackColor: const Color(0xFF38BDF8),
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: const Color(0xFF38BDF8),
                                            overlayColor: const Color(0xFF38BDF8).withOpacity(0.2),
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                            trackHeight: 3.0,
                                          ),
                                          child: Slider(
                                            focusNode: FocusNode(canRequestFocus: false),
                                            value: _isMuted ? 0.0 : _volume,
                                            min: 0.0,
                                            max: 1.0,
                                            onChanged: (val) {
                                              _startHideControlsTimer();
                                              _setVolume(val);
                                            },
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _isMuted ? '0%' : '${(_volume * 100).round()}%',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Center: Clean transparent space (No screen darkening, No blocking buttons)
                      const Spacer(),

                      // Bottom Bar with Timeline & Playback Controls Below Progress Bar
                      MouseRegion(
                        onEnter: (_) {
                          _isHoveringControls = true;
                          _hideControlsTimer?.cancel();
                        },
                        onExit: (_) {
                          _isHoveringControls = false;
                          _startHideControlsTimer();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.75),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress Slider for VOD (Thanh tiến trình)
                              if (!widget.isLive && _isInitialized) ...[
                                Focus(
                                  focusNode: _seekBarFocusNode,
                                  child: AnimatedBuilder(
                                    animation: _seekBarFocusNode,
                                    builder: (context, child) {
                                      final bool isFocused = _seekBarFocusNode.hasFocus;
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isFocused ? const Color(0xFF38BDF8) : Colors.transparent,
                                            width: 1.5,
                                          ),
                                          color: isFocused ? const Color(0xFF38BDF8).withOpacity(0.08) : Colors.transparent,
                                        ),
                                        child: child,
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        Text(
                                          _formatDuration(_isHoldingSeek ? _pendingSeekPosition : _controller.value.position),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: MouseRegion(
                                            cursor: SystemMouseCursors.click,
                                            child: SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                activeTrackColor: const Color(0xFF38BDF8),
                                                inactiveTrackColor: Colors.white24,
                                                thumbColor: const Color(0xFF38BDF8),
                                                overlayColor: const Color(0xFF38BDF8).withOpacity(0.2),
                                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                                                trackHeight: 4.0,
                                              ),
                                              child: Slider(
                                                focusNode: FocusNode(canRequestFocus: false),
                                                value: (_isHoldingSeek ? _pendingSeekPosition : _controller.value.position).inSeconds.toDouble().clamp(
                                                      0.0,
                                                      _controller.value.duration.inSeconds.toDouble(),
                                                    ),
                                                max: _controller.value.duration.inSeconds.toDouble() > 0
                                                    ? _controller.value.duration.inSeconds.toDouble()
                                                    : 1.0,
                                                onChangeStart: (val) {
                                                  _hideControlsTimer?.cancel();
                                                  setState(() {
                                                    _isHoldingSeek = true;
                                                    _pendingSeekPosition = Duration(seconds: val.toInt());
                                                  });
                                                },
                                                onChanged: (val) {
                                                  setState(() {
                                                    _pendingSeekPosition = Duration(seconds: val.toInt());
                                                  });
                                                },
                                                onChangeEnd: (val) {
                                                  final target = Duration(seconds: val.toInt());
                                                  _controller.seekTo(target).then((_) {
                                                    if (mounted) {
                                                      setState(() {
                                                        _isHoldingSeek = false;
                                                      });
                                                      _startHideControlsTimer();
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDuration(_controller.value.duration),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // Playback Controls Row (Nút điều khiển xuất hiện DƯỚI thanh tiến trình)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (widget.onPrevious != null) ...[
                                    TvFocusableCard(
                                      focusNode: _prevFocusNode,
                                      onTap: widget.onPrevious!,
                                      scale: 1.15,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 26),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                  ],
                                  if (!widget.isLive) ...[
                                    TvFocusableCard(
                                      focusNode: _replay10FocusNode,
                                      onTap: () => _seekRelative(-10),
                                      scale: 1.15,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 26),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                  ],
                                  TvFocusableCard(
                                    focusNode: _playPauseFocusNode,
                                    onTap: _togglePlayPause,
                                    scale: 1.15,
                                    borderRadius: BorderRadius.circular(30),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF38BDF8).withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                        color: const Color(0xFF38BDF8),
                                        size: 46,
                                      ),
                                    ),
                                  ),
                                  if (!widget.isLive) ...[
                                    const SizedBox(width: 14),
                                    TvFocusableCard(
                                      focusNode: _forward10FocusNode,
                                      onTap: () => _seekRelative(10),
                                      scale: 1.15,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 26),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TvFocusableCard(
                                      focusNode: _skipIntroFocusNode,
                                      onTap: () => _seekDirectOffset(85, customHudText: '+85s (Bỏ qua Intro)'),
                                      scale: 1.05,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF38BDF8).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4), width: 0.8),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.fast_forward_rounded, color: Color(0xFF38BDF8), size: 16),
                                            SizedBox(width: 4),
                                            Text(
                                              '+85s Intro',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (widget.onNext != null) ...[
                                    const SizedBox(width: 14),
                                    TvFocusableCard(
                                      focusNode: _nextFocusNode,
                                      onTap: widget.onNext!,
                                      scale: 1.15,
                                      borderRadius: BorderRadius.circular(24),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 26),
                                      ),
                                    ),
                                  ],
                                  if (_effectiveChannels.isNotEmpty) ...[
                                    const SizedBox(width: 14),
                                    TvFocusableCard(
                                      focusNode: _channelsButtonFocusNode,
                                      onTap: () {
                                        setState(() {
                                          _showStreamSelector = !_showStreamSelector;
                                        });
                                        if (_showStreamSelector) {
                                          _initChannelFocusNodes();
                                          _startHideControlsTimer();
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            _focusActiveChannel();
                                          });
                                        } else {
                                          _startHideControlsTimer();
                                        }
                                      },
                                      scale: 1.08,
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _showStreamSelector
                                              ? const Color(0xFF0284C7)
                                              : Colors.white.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: _showStreamSelector ? const Color(0xFF38BDF8) : Colors.white24,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.dns_rounded, color: Colors.white, size: 15),
                                            const SizedBox(width: 6),
                                            Text(
                                              _getActiveChannelTitleShort(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ),

              // 5.5 VERTICAL STREAM SELECTOR PANEL
              if (_showStreamSelector && _effectiveChannels.isNotEmpty)
                Positioned(
                  bottom: 96,
                  right: 28,
                  child: MouseRegion(
                    onEnter: (_) {
                      _isHoveringControls = true;
                      _hideControlsTimer?.cancel();
                    },
                    onExit: (_) {
                      _isHoveringControls = false;
                      _startHideControlsTimer();
                    },
                    child: Container(
                      width: 380,
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.96),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.8),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.dns_rounded, color: Color(0xFF38BDF8), size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'DANH SÁCH LUỒNG PHÁT',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _showStreamSelector = false;
                                  });
                                  _channelsButtonFocusNode.requestFocus();
                                  _startHideControlsTimer();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _effectiveChannels.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final ch = _effectiveChannels[index];
                                final bool isSelected = ch.url == _currentStreamUrl;
                                final node = index < _channelFocusNodes.length ? _channelFocusNodes[index] : null;
                                return Focus(
                                  onKeyEvent: (focusNode, event) {
                                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                                      setState(() {
                                        _showStreamSelector = false;
                                      });
                                      _channelsButtonFocusNode.requestFocus();
                                      _startHideControlsTimer();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TvFocusableCard(
                                    focusNode: node,
                                    onTap: () {
                                      _switchChannel(ch);
                                      _startHideControlsTimer(); // restart 5s idle timer
                                      // Bảng không đóng ngay để người dùng test luồng mới
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF0284C7).withOpacity(0.4)
                                          : Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF38BDF8) : Colors.white12,
                                        width: isSelected ? 1.5 : 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          color: isSelected ? const Color(0xFF38BDF8) : Colors.white38,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            ch.title,
                                            style: TextStyle(
                                              color: isSelected ? Colors.white : Colors.white70,
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 6. NEXT EPISODE COUNTDOWN OVERLAY
              if (_nextCountdownSeconds > 0)
                Positioned(
                  bottom: _showControls ? 140 : 36,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.7),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'TẬP TIẾP THEO',
                              style: TextStyle(
                                color: Color(0xFF38BDF8),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tự động phát sau ${_nextCountdownSeconds}s...',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        TvFocusableCard(
                          onTap: _playNextEpisodeImmediately,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                                SizedBox(width: 2),
                                Text('Phát Ngay', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        TvFocusableCard(
                          onTap: _cancelNextCountdown,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Hủy', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // 5. FLOATING UNLOCK BUTTON (Hiển thị khi khóa màn hình cảm ứng)
              if (_isScreenLocked)
                Positioned(
                  top: 24,
                  left: 24,
                  child: SafeArea(
                    child: AnimatedOpacity(
                      opacity: _showLockOverlay ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !_showLockOverlay,
                        child: GestureDetector(
                          onTap: _toggleLockScreen,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xE60F172A),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF38BDF8).withOpacity(0.35),
                                  blurRadius: 14,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_rounded, color: Color(0xFF38BDF8), size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Chạm để mở khóa',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}
