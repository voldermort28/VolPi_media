import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/anime_model.dart';
import '../models/match_model.dart';
import '../models/watch_history_model.dart';
import '../services/audio_player_handler.dart';
import '../services/player_settings_service.dart';
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
  final List<EpisodeModel>? episodes;
  final int currentEpisodeIndex;
  final ValueChanged<int>? onSelectEpisode;

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
    this.episodes,
    this.currentEpisodeIndex = -1,
    this.onSelectEpisode,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();

  static DateTime? lastExitTime;
  static bool isRecentExit([int thresholdMs = 600]) {
    if (lastExitTime == null) return false;
    return DateTime.now().difference(lastExitTime!).inMilliseconds < thresholdMs;
  }
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with WidgetsBindingObserver {
  Timer? _saveProgressTimer;
  DateTime? _lastBackHandledTime;
  VideoPlayerController? _controller;
  int _initGeneration = 0;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showControls = true;
  Timer? _hideControlsTimer;
  late String _currentStreamUrl;
  late String _currentTitle;
  late Map<String, String> _currentHeaders;

  // Live auto-reconnect & mid-playback buffering state
  int _reconnectAttempts = 0;
  static const int _maxLiveReconnects = 3;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  bool _lastIsBuffering = false;
  bool _lastIsPlaying = false;
  bool _isSwitchingEpisode = false;

  // Playback Speed & Aspect Ratio (Zoom) + Mobile Software Brightness
  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];
  double _playbackSpeed = 1.0;
  int _aspectModeIndex = 0; // 0: Vừa (Fit), 1: Lấp đầy (Fill/Cover), 2: 16:9, 3: 4:3
  static const List<String> _aspectModeLabels = ['Vừa', 'Lấp đầy', '16:9', '4:3'];
  double _softwareBrightness = 1.0; // 0.25 .. 1.0 (Mobile left-side vertical swipe)
  bool _isVerticalDragging = false;
  bool _verticalDragIsLeft = false;

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
  int _doubleTapAccumulatedSeconds = 0;
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
  bool _showEpisodeSelector = false;

  // TV Remote Focus Nodes (all reusable State fields — never created inside build)
  final FocusNode _rootFocusNode = FocusNode();
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _seekBarFocusNode = FocusNode();
  final FocusNode _prevFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _replay10FocusNode = FocusNode();
  final FocusNode _forward10FocusNode = FocusNode();
  final FocusNode _skipIntroFocusNode = FocusNode();
  final FocusNode _speedButtonFocusNode = FocusNode();
  final FocusNode _aspectButtonFocusNode = FocusNode();
  final FocusNode _episodesButtonFocusNode = FocusNode();
  final FocusNode _channelsButtonFocusNode = FocusNode();
  final FocusNode _backButtonFocusNode = FocusNode();
  final FocusNode _rotateFocusNode = FocusNode();
  final FocusNode _lockFocusNode = FocusNode();
  final FocusNode _volumeSliderFocusNode = FocusNode(canRequestFocus: false);
  final FocusNode _progressSliderFocusNode = FocusNode(canRequestFocus: false);
  final FocusNode _errorRetryFocusNode = FocusNode();
  final FocusNode _countdownPlayFocusNode = FocusNode();
  final FocusNode _countdownCancelFocusNode = FocusNode();
  final List<FocusNode> _channelFocusNodes = [];
  final List<FocusNode> _episodeFocusNodes = [];
  bool _lastFocusedOnSeekBar = true;

  // Screen Orientation & Touch Lock (Mobile / iOS / Tablet)
  bool _isScreenLocked = false;
  bool _showLockOverlay = false;
  Timer? _lockOverlayTimer;

  // Touch Hold Fast Forward (2x -> 3x Telegram Style)
  bool _isHoldSpeeding = false;
  double _currentHoldSpeed = 1.0;
  bool _wasPlayingBeforeHold = true;
  Offset? _holdStartOffset;

  List<StreamChannel> get _effectiveChannels {
    if (widget.availableChannels != null && widget.availableChannels!.isNotEmpty) {
      return widget.availableChannels!;
    }
    return [
      StreamChannel(
        name: 'Server 1',
        title: widget.subtitle.isNotEmpty ? widget.subtitle : 'Full HD (Mặc định)',
        url: _currentStreamUrl.isNotEmpty ? _currentStreamUrl : widget.streamUrl,
        headers: widget.headers,
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
      list.add(_speedButtonFocusNode);
    }
    list.add(_aspectButtonFocusNode);
    if (widget.onNext != null) list.add(_nextFocusNode);
    if (widget.episodes != null && widget.episodes!.isNotEmpty && widget.onSelectEpisode != null) {
      list.add(_episodesButtonFocusNode);
    }
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

  void _initEpisodeFocusNodes() {
    for (final node in _episodeFocusNodes) {
      node.dispose();
    }
    _episodeFocusNodes.clear();
    final count = widget.episodes?.length ?? 0;
    for (int i = 0; i < count; i++) {
      _episodeFocusNodes.add(FocusNode());
    }
  }

  void _focusCurrentEpisode() {
    if (!mounted || !_showEpisodeSelector || _episodeFocusNodes.isEmpty) return;
    int activeIdx = widget.currentEpisodeIndex;
    if (activeIdx < 0 && widget.episode > 0 && widget.episodes != null) {
      activeIdx = widget.episodes!.indexWhere((e) => e.episode == widget.episode);
    }
    if (activeIdx < 0 || activeIdx >= _episodeFocusNodes.length) activeIdx = 0;
    if (activeIdx < _episodeFocusNodes.length) {
      _episodeFocusNodes[activeIdx].requestFocus();
    }
  }

  void _exitPlayer() {
    if (_isScreenLocked) {
      setState(() {
        _showLockOverlay = true;
      });
      _startLockOverlayTimer();
      _showBriefPlaybackHud('LOCK', 'Màn hình đang khóa');
      return;
    }
    VideoPlayerScreen.lastExitTime = DateTime.now();
    Navigator.of(context).pop();
  }

  void _handleBackAction() {
    final now = DateTime.now();
    if (_lastBackHandledTime != null &&
        now.difference(_lastBackHandledTime!).inMilliseconds < 400) {
      return;
    }
    _lastBackHandledTime = now;

    if (_isScreenLocked) {
      setState(() {
        _showLockOverlay = true;
      });
      _startLockOverlayTimer();
      _showBriefPlaybackHud('LOCK', 'Màn hình đang khóa');
      return;
    }
    if (_showEpisodeSelector) {
      setState(() {
        _showEpisodeSelector = false;
      });
      _episodesButtonFocusNode.requestFocus();
      _startHideControlsTimer();
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
    if (_nextCountdownSeconds > 0 && !_showControls) {
      _cancelNextCountdown();
      _rootFocusNode.requestFocus();
      return;
    }
    if (_showControls) {
      setState(() {
        _showControls = false;
      });
      _hideControlsTimer?.cancel();
      _rootFocusNode.requestFocus();
      return;
    }
    _exitPlayer();
  }

  bool get _isMacOrDesktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _isIOS => !kIsWeb && Platform.isIOS;
  bool get _isTouchMobile {
    if (_isIOS) return true;
    if (!kIsWeb && Platform.isAndroid) {
      final mq = MediaQuery.maybeOf(context);
      if (mq != null && (mq.orientation == Orientation.portrait || mq.size.shortestSide < 460)) {
        return true;
      }
    }
    return false;
  }

  void _setWakelock(bool enable) {
    try {
      final fut = enable ? WakelockPlus.enable() : WakelockPlus.disable();
      unawaited(fut.catchError((_) {}));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tạm dừng nhạc nền nếu đang phát trước khi mở video
    VolPiAudioHandler.instance.pauseIfPlaying();

    _currentStreamUrl = widget.streamUrl;
    _currentTitle = widget.title;
    _currentHeaders = widget.headers;
    _volume = PlayerSettingsService.instance.volume;
    _isMuted = PlayerSettingsService.instance.isMuted;
    _preMuteVolume = PlayerSettingsService.instance.preMuteVolume;

    _seekBarFocusNode.addListener(() {
      if (_seekBarFocusNode.hasFocus) {
        _lastFocusedOnSeekBar = true;
      }
    });
    _playPauseFocusNode.addListener(() {
      if (_playPauseFocusNode.hasFocus) {
        _lastFocusedOnSeekBar = false;
      }
    });
    _backButtonFocusNode.addListener(() {
      if (_backButtonFocusNode.hasFocus) {
        _lastFocusedOnSeekBar = false;
      }
    });
    for (final node in [
      _prevFocusNode,
      _nextFocusNode,
      _replay10FocusNode,
      _forward10FocusNode,
      _skipIntroFocusNode,
      _speedButtonFocusNode,
      _aspectButtonFocusNode,
      _episodesButtonFocusNode,
      _channelsButtonFocusNode,
    ]) {
      node.addListener(() {
        if (node.hasFocus) {
          _lastFocusedOnSeekBar = false;
        }
      });
    }

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setWakelock(true);
    _initPlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveCurrentProgress(triggerSync: true);
      WatchHistoryService.instance.flush();
      _setWakelock(false);
    } else if (state == AppLifecycleState.resumed) {
      if (_isInitialized && (_controller?.value.isPlaying ?? false)) {
        _setWakelock(true);
      }
    }
  }

  Future<void> _initPlayer({Duration? resumePosition, bool isReconnect = false}) async {
    final int gen = ++_initGeneration;
    _reconnectTimer?.cancel();
    if (!isReconnect) {
      _reconnectAttempts = 0;
    }

    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      try {
        oldController.removeListener(_videoListener);
        oldController.dispose();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
        _isReconnecting = isReconnect;
        _lastIsBuffering = false;
      });
    }

    VideoPlayerController? newController;
    try {
      final parsedUri = Uri.parse(_currentStreamUrl.trim());
      newController = VideoPlayerController.networkUrl(
        parsedUri,
        httpHeaders: _currentHeaders,
      );

      await newController.initialize();
      if (!mounted || gen != _initGeneration) {
        try {
          await newController.dispose();
        } catch (_) {}
        return;
      }

      final double targetVol = _isMuted ? 0.0 : _volume;
      await newController.setVolume(targetVol);
      if (!widget.isLive && _playbackSpeed != 1.0) {
        try {
          await newController.setPlaybackSpeed(_playbackSpeed);
        } catch (_) {}
      }

      final Duration? targetPos = resumePosition ?? widget.initialPosition;
      if (!widget.isLive && targetPos != null && targetPos > Duration.zero) {
        await newController.seekTo(targetPos);
      }
      if (!mounted || gen != _initGeneration) {
        try {
          await newController.dispose();
        } catch (_) {}
        return;
      }

      await newController.play();
      if (!mounted || gen != _initGeneration) {
        try {
          await newController.dispose();
        } catch (_) {}
        return;
      }

      await newController.setVolume(targetVol);
      _controller = newController;
      _reconnectAttempts = 0;
      _isReconnecting = false;
      _lastIsPlaying = true;
      _setWakelock(true);

      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && gen == _initGeneration && _controller != null && _isInitialized) {
          _controller!.setVolume(_isMuted ? 0.0 : _volume);
        }
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && gen == _initGeneration && _controller != null && _isInitialized) {
          _controller!.setVolume(_isMuted ? 0.0 : _volume);
        }
      });

      newController.addListener(_videoListener);

      if (mounted && gen == _initGeneration) {
        setState(() {
          _isInitialized = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || gen != _initGeneration || !_showControls) return;
          if (_showStreamSelector || _showEpisodeSelector) return;
          if (!widget.isLive) {
            _lastFocusedOnSeekBar = true;
            _seekBarFocusNode.requestFocus();
          } else {
            _lastFocusedOnSeekBar = false;
            _playPauseFocusNode.requestFocus();
          }
        });
        _startHideControlsTimer();
        _saveProgressTimer?.cancel();
        _saveProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
          // Chỉ lưu cục bộ RAM + đĩa mỗi 5s, KHÔNG đẩy HTTP Sync mỗi 5s
          _saveCurrentProgress(triggerSync: false);
        });
      }
    } catch (e) {
      if (newController != null && newController != _controller) {
        try {
          await newController.dispose();
        } catch (_) {}
      }
      if (!mounted || gen != _initGeneration) return;

      // Tự động kết nối lại tối đa 3 lần đối với luồng Live/IPTV
      if (widget.isLive && _reconnectAttempts < _maxLiveReconnects) {
        _scheduleLiveReconnect();
        return;
      }

      _setWakelock(false);
      final errStr = e.toString();
      String friendlyError = 'Không thể phát luồng này: $errStr';

      if (errStr.contains('12939') ||
          (errStr.contains('length') && errStr.contains('2040')) ||
          errStr.contains('429') ||
          errStr.contains('QUOTA_EXCEEDED') ||
          errStr.contains('Quota exceeded')) {
        friendlyError =
            'File này đã bị Google Drive giới hạn lượt tải công khai trong 24 giờ (Quota Exceeded).\n\n'
            '💡 Cách khắc phục: Vui lòng mở trang web quản trị https://stremio.laboon.vn/gdrive '
            'và kết nối Tài Khoản Google của bạn để phát không giới hạn!';
      }

      setState(() {
        _hasError = true;
        _isReconnecting = false;
        _errorMessage = friendlyError;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hasError && _errorRetryFocusNode.canRequestFocus) {
          _errorRetryFocusNode.requestFocus();
        }
      });
    }
  }

  void _scheduleLiveReconnect() {
    _reconnectAttempts++;
    final int delaySec = _reconnectAttempts * 2;
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _hasError = false;
        _isReconnecting = true;
      });
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (mounted) {
        _initPlayer(isReconnect: true);
      }
    });
  }

  void _videoListener() {
    final ctrl = _controller;
    if (!mounted || !_isInitialized || ctrl == null) return;
    final val = ctrl.value;

    // 1. Bắt lỗi phát sinh giữa chừng (rớt mạng / hết hạn token HLS / đứt luồng IPTV)
    if (val.hasError) {
      final errDesc = val.errorDescription ?? 'Kết nối luồng phát bị gián đoạn';
      if (widget.isLive && _reconnectAttempts < _maxLiveReconnects) {
        _scheduleLiveReconnect();
        return;
      }
      _setWakelock(false);
      setState(() {
        _isInitialized = false;
        _hasError = true;
        _isReconnecting = false;
        _errorMessage = 'Luồng phát bị ngắt giữa chừng: $errDesc';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hasError && _errorRetryFocusNode.canRequestFocus) {
          _errorRetryFocusNode.requestFocus();
        }
      });
      return;
    }

    // 2. Đồng bộ Wakelock theo trạng thái Play/Pause
    if (val.isPlaying != _lastIsPlaying) {
      _lastIsPlaying = val.isPlaying;
      _setWakelock(val.isPlaying);
    }

    // 3. Cập nhật UI ngay lập tức khi chuyển trạng thái Buffering (ngay cả khi OSD đang ẩn!)
    final bool bufferingChanged = val.isBuffering != _lastIsBuffering;
    if (bufferingChanged) {
      _lastIsBuffering = val.isBuffering;
    }

    // 4. Tự động đếm ngược Tập tiếp theo (và hủy nếu người dùng tua ngược lại)
    if (widget.onNext != null && !widget.isLive) {
      final pos = val.position;
      final dur = val.duration;
      if (_nextCountdownSeconds > 0 && dur > const Duration(seconds: 30) && pos < dur - const Duration(seconds: 20)) {
        _cancelNextCountdown();
        _hasTriggeredNextCountdown = false;
      } else if (!_hasTriggeredNextCountdown &&
          dur > const Duration(seconds: 30) &&
          (pos >= dur - const Duration(seconds: 15) || (!dur.isNegative && pos >= dur && dur > Duration.zero))) {
        _startNextEpisodeCountdown();
      }
    }

    // Chỉ rebuild UI khi OSD mở, đang đếm ngược hoặc trạng thái buffering vừa đổi
    if (_showControls || _nextCountdownSeconds > 0 || bufferingChanged) {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _nextCountdownSeconds > 0 && !_showControls && _countdownPlayFocusNode.canRequestFocus) {
        _countdownPlayFocusNode.requestFocus();
      }
    });
  }

  void _triggerEpisodeCallback(VoidCallback? callback) {
    if (callback == null || _isSwitchingEpisode) return;
    _isSwitchingEpisode = true;
    _nextCountdownTimer?.cancel();
    _nextCountdownTimer = null;
    if (mounted) {
      setState(() {
        _nextCountdownSeconds = 0;
      });
    }
    _saveCurrentProgress(triggerSync: true);
    WatchHistoryService.instance.flush();
    try {
      _controller?.pause();
    } catch (_) {}
    callback();
    Future.delayed(const Duration(seconds: 3), () {
      _isSwitchingEpisode = false;
    });
  }

  void _playNextEpisodeImmediately() {
    _triggerEpisodeCallback(widget.onNext);
  }

  void _cancelNextCountdown() {
    setState(() {
      _nextCountdownTimer?.cancel();
      _nextCountdownTimer = null;
      _nextCountdownSeconds = 0;
    });
  }

  void _cyclePlaybackSpeed() {
    if (widget.isLive || !_isInitialized || _controller == null) return;
    final idx = _speedOptions.indexOf(_playbackSpeed);
    final nextSpeed = _speedOptions[(idx + 1) % _speedOptions.length];
    setState(() {
      _playbackSpeed = nextSpeed;
    });
    try {
      _controller!.setPlaybackSpeed(nextSpeed);
    } catch (_) {}
    _showBriefPlaybackHud('SPEED', 'Tốc độ ${nextSpeed}x');
  }

  void _cycleAspectMode() {
    setState(() {
      _aspectModeIndex = (_aspectModeIndex + 1) % _aspectModeLabels.length;
    });
    _showBriefPlaybackHud('ASPECT', 'Khung hình: ${_aspectModeLabels[_aspectModeIndex]}');
  }

  void _seekDirectOffset(int seconds, {String? customHudText}) {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null || widget.isLive) return;
    final currentPos = ctrl.value.position;
    final totalDuration = ctrl.value.duration;
    if (totalDuration <= Duration.zero) return;
    final targetSeconds = (currentPos.inSeconds + seconds).clamp(0, totalDuration.inSeconds);
    final target = Duration(seconds: targetSeconds);
    ctrl.seekTo(target);
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
    if (_isInitialized && _controller != null) {
      _controller!.setVolume(_isMuted ? 0.0 : _volume);
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
    Duration? lastPos;
    if (_isInitialized && !widget.isLive && _controller != null) {
      try {
        lastPos = _controller!.value.position;
      } catch (_) {}
    }
    setState(() {
      _currentStreamUrl = channel.url;
      // Chỉ cập nhật tiêu đề theo tên kênh khi xem Live TV / Bóng đá; không ghi đè tên phim VOD bằng "Server #2"
      if (widget.isLive) {
        _currentTitle = channel.title;
      }
      _currentHeaders = channel.headers;
    });
    _initPlayer(resumePosition: lastPos);
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
    final duration = (_showStreamSelector || _showEpisodeSelector)
        ? const Duration(seconds: 15)
        : const Duration(seconds: 6);
    _hideControlsTimer = Timer(duration, () {
      if (mounted &&
          (_controller?.value.isPlaying ?? false) &&
          !_isDragging &&
          !_isHoldingSeek &&
          !_isHoveringControls) {
        setState(() {
          _showControls = false;
          _showStreamSelector = false;
          _showEpisodeSelector = false;
        });
        _rootFocusNode.requestFocus();
      }
    });
  }

  void _toggleScreenOrientation() {
    if (!_isTouchMobile) return;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      _showBriefPlaybackHud('ROTATE', 'Màn hình dọc');
    } else {
      // Ép duy nhất landscapeRight để xoay đúng chiều ngược lại so với mặc định cũ (landscapeLeft)
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
      ]);
      _showBriefPlaybackHud('ROTATE', 'Màn hình ngang');
    }
  }

  void _toggleLockScreen() {
    if (!_isTouchMobile) return;
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

  void _showControlsBriefly({bool focusSeekBar = false, bool focusControls = false}) {
    if (_isScreenLocked) return;
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showControls) return;
      if (focusControls) {
        _lastFocusedOnSeekBar = false;
        _playPauseFocusNode.requestFocus();
        return;
      }
      if (!widget.isLive && (focusSeekBar || _lastFocusedOnSeekBar)) {
        _seekBarFocusNode.requestFocus();
        return;
      }
      final anyFocused = _getActiveControlNodes().any((n) => n.hasFocus) ||
          _seekBarFocusNode.hasFocus ||
          _backButtonFocusNode.hasFocus;
      if (!anyFocused) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  void _toggleControls() {
    if (_isScreenLocked) return;
    if (_showStreamSelector || _showEpisodeSelector) {
      setState(() {
        _showStreamSelector = false;
        _showEpisodeSelector = false;
        _showControls = false;
      });
      _hideControlsTimer?.cancel();
      _rootFocusNode.requestFocus();
      return;
    }
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showControls) return;
        final anyFocused = _getActiveControlNodes().any((n) => n.hasFocus) ||
            _seekBarFocusNode.hasFocus ||
            _backButtonFocusNode.hasFocus;
        if (!anyFocused) {
          if (!widget.isLive && _lastFocusedOnSeekBar) {
            _seekBarFocusNode.requestFocus();
          } else {
            _playPauseFocusNode.requestFocus();
          }
        }
      });
    } else {
      _hideControlsTimer?.cancel();
      _rootFocusNode.requestFocus();
    }
  }

  void _playVideo() {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null) return;
    if (!ctrl.value.isPlaying) {
      ctrl.play();
    }
    _setWakelock(true);
    _showBriefPlaybackHud('PLAY', 'Đang phát');
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _pauseVideo() {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    }
    _setWakelock(false);
    _saveCurrentProgress(triggerSync: true);
    WatchHistoryService.instance.flush();
    _showBriefPlaybackHud('PAUSE', 'Tạm dừng');
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer?.cancel();
  }

  void _togglePlayPause() {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null) return;
    if (ctrl.value.isPlaying) {
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

  Duration get _videoBufferedPosition {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null) return Duration.zero;
    final buffered = ctrl.value.buffered;
    if (buffered.isEmpty) return Duration.zero;
    final pos = ctrl.value.position;
    for (final range in buffered) {
      if (pos >= range.start && pos <= range.end) {
        return range.end;
      }
    }
    return buffered.last.end;
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
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null || widget.isLive) return;
    _lastFocusedOnSeekBar = true;

    final now = DateTime.now();

    if (!_isHoldingSeek || _holdSeekDirection != direction) {
      _isHoldingSeek = true;
      _holdSeekDirection = direction;
      _holdStartTime = now;
      _holdRepeatCount = 0;
      _pendingSeekPosition = ctrl.value.position;
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
    final ctrl = _controller;
    if (ctrl == null) return;
    final duration = ctrl.value.duration;
    final step = Duration(seconds: stepSeconds * direction);

    _seekAccumulatedDelta += step;
    final newPos = _pendingSeekPosition + step;
    _pendingSeekPosition = newPos < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && newPos > duration ? duration : newPos);

    _hudFadeTimer?.cancel();
    setState(() {
      _hudIcon = direction > 0 ? 'FORWARD' : 'REWIND';
      _hudText = _formatDelta(_seekAccumulatedDelta, direction);
      _hudSpeedBadge = speedBadge;
      _dragTargetPosition = _pendingSeekPosition;
    });

    _showControlsBriefly(focusSeekBar: true);

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
    final ctrl = _controller;
    if (!_isHoldingSeek || !_isInitialized || ctrl == null || widget.isLive) {
      _isHoldingSeek = false;
      return;
    }

    final target = _pendingSeekPosition;
    _isHoldingSeek = false;
    _holdRepeatCount = 0;
    _holdStartTime = null;

    ctrl.seekTo(target);

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

  // --- Touch Gestures Handling (iOS & Android Phone) ---
  void _onHorizontalDragStart(DragStartDetails details) {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null || widget.isLive) return;
    _dragStartPosition = ctrl.value.position;
    _dragTargetPosition = _dragStartPosition;
    _dragTotalDeltaX = 0.0;
    _isDragging = true;
    _hudFadeTimer?.cancel();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null || widget.isLive || !_isDragging) return;
    final duration = ctrl.value.duration;
    if (duration <= Duration.zero) return;
    _dragTotalDeltaX += details.primaryDelta ?? 0.0;

    // 1px drag = ~0.4s seek
    final deltaSeconds = (_dragTotalDeltaX * 0.4).toInt();
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
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null || widget.isLive || !_isDragging) return;
    _isDragging = false;
    ctrl.seekTo(_dragTargetPosition);

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

  // --- Mobile Vertical Drag: Left Half = Software Brightness, Right Half = Volume ---
  void _onVerticalDragStart(DragStartDetails details) {
    if (!_isTouchMobile || _isScreenLocked) return;
    final width = MediaQuery.of(context).size.width;
    _isVerticalDragging = true;
    _verticalDragIsLeft = details.localPosition.dx < width * 0.5;
    _hudFadeTimer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDragging || _isScreenLocked) return;
    final dy = details.primaryDelta ?? 0.0;
    final delta = -dy / 240.0; // Drag up increases, drag down decreases
    if (_verticalDragIsLeft) {
      setState(() {
        _softwareBrightness = (_softwareBrightness + delta).clamp(0.25, 1.0);
        _hudIcon = 'BRIGHTNESS';
        _hudText = '${(_softwareBrightness * 100).round()}%';
        _hudSpeedBadge = 'Độ sáng';
      });
    } else {
      final target = ((_isMuted ? 0.0 : _volume) + delta).clamp(0.0, 1.0);
      _setVolume(target);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isVerticalDragging) return;
    _isVerticalDragging = false;
    _hudFadeTimer?.cancel();
    _hudFadeTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && (_hudIcon == 'BRIGHTNESS' || (_hudIcon?.startsWith('VOLUME') ?? false))) {
        setState(() {
          _hudIcon = null;
          _hudText = null;
          _hudSpeedBadge = null;
        });
      }
    });
  }

  // --- Telegram-Style Hold & Swipe Fast Forward (2x -> 3x) ---
  void _onLongPressStart(LongPressStartDetails details) {
    final ctrl = _controller;
    if (!_isTouchMobile || !_isInitialized || ctrl == null || widget.isLive || _isScreenLocked) return;
    _holdStartOffset = details.localPosition;
    _isHoldSpeeding = true;
    _wasPlayingBeforeHold = ctrl.value.isPlaying;
    _currentHoldSpeed = 2.0;

    if (!ctrl.value.isPlaying) {
      ctrl.play();
    }
    ctrl.setPlaybackSpeed(2.0);

    _hideControlsTimer?.cancel();
    setState(() {
      _showControls = false;
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final ctrl = _controller;
    if (!_isHoldSpeeding || !_isInitialized || ctrl == null || widget.isLive || _isScreenLocked) return;
    if (_holdStartOffset == null) return;

    final deltaX = details.localPosition.dx - _holdStartOffset!.dx;
    final double targetSpeed = deltaX > 40 ? 3.0 : 2.0;

    if (targetSpeed != _currentHoldSpeed) {
      _currentHoldSpeed = targetSpeed;
      ctrl.setPlaybackSpeed(_currentHoldSpeed);
      setState(() {});
    }
  }

  void _onLongPressEnd(LongPressEndDetails? details) {
    if (!_isHoldSpeeding) return;
    _isHoldSpeeding = false;
    _holdStartOffset = null;
    _currentHoldSpeed = 1.0;

    final ctrl = _controller;
    if (_isInitialized && ctrl != null) {
      ctrl.setPlaybackSpeed(_playbackSpeed);
      if (!_wasPlayingBeforeHold) {
        ctrl.pause();
      }
    }
    setState(() {});
  }

  void _onLongPressCancel() {
    _onLongPressEnd(null);
  }

  void _onDoubleTapSide(bool isRight) {
    final ctrl = _controller;
    if (!_isInitialized || ctrl == null || widget.isLive) return;
    final dur = ctrl.value.duration;
    if (dur <= Duration.zero) return;

    // Reset accumulation if switching sides
    if ((isRight && _showDoubleTapLeft) || (!isRight && _showDoubleTapRight)) {
      _doubleTapAccumulatedSeconds = 0;
    }
    _doubleTapAccumulatedSeconds += 10;

    // Tua trực tiếp tức thì không bung OSD (chuẩn YouTube Mobile)
    final targetSec = (ctrl.value.position.inSeconds + (isRight ? 10 : -10)).clamp(0, dur.inSeconds);
    ctrl.seekTo(Duration(seconds: targetSec));
    _doubleTapTimer?.cancel();

    setState(() {
      if (isRight) {
        _showDoubleTapRight = true;
        _showDoubleTapLeft = false;
      } else {
        _showDoubleTapLeft = true;
        _showDoubleTapRight = false;
      }
    });

    _doubleTapTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _showDoubleTapLeft = false;
          _showDoubleTapRight = false;
          _doubleTapAccumulatedSeconds = 0;
        });
      }
    });
  }

  void _saveCurrentProgress({bool triggerSync = true}) {
    final ctrl = _controller;
    if (!mounted || !_isInitialized || ctrl == null || widget.isLive || widget.mediaId == null || widget.mediaId!.isEmpty) return;
    try {
      final pos = ctrl.value.position;
      final dur = ctrl.value.duration;
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
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        ),
        triggerSync: triggerSync,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _initGeneration++;
    _reconnectTimer?.cancel();
    _saveProgressTimer?.cancel();
    _saveCurrentProgress(triggerSync: true);
    WatchHistoryService.instance.flush();
    _setWakelock(false);
    _hideControlsTimer?.cancel();
    _lockOverlayTimer?.cancel();
    _nextCountdownTimer?.cancel();
    _hudFadeTimer?.cancel();
    _doubleTapTimer?.cancel();
    _commitSeekTimer?.cancel();
    final ctrl = _controller;
    _controller = null;
    if (ctrl != null) {
      if (_isHoldSpeeding) {
        try {
          ctrl.setPlaybackSpeed(1.0);
        } catch (_) {}
      }
      try {
        ctrl.removeListener(_videoListener);
        ctrl.dispose();
      } catch (_) {}
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    _rootFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _seekBarFocusNode.dispose();
    _prevFocusNode.dispose();
    _nextFocusNode.dispose();
    _replay10FocusNode.dispose();
    _forward10FocusNode.dispose();
    _skipIntroFocusNode.dispose();
    _speedButtonFocusNode.dispose();
    _aspectButtonFocusNode.dispose();
    _episodesButtonFocusNode.dispose();
    _channelsButtonFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _rotateFocusNode.dispose();
    _lockFocusNode.dispose();
    _volumeSliderFocusNode.dispose();
    _progressSliderFocusNode.dispose();
    _errorRetryFocusNode.dispose();
    _countdownPlayFocusNode.dispose();
    _countdownCancelFocusNode.dispose();
    for (final n in _channelFocusNodes) {
      n.dispose();
    }
    _channelFocusNodes.clear();
    for (final n in _episodeFocusNodes) {
      n.dispose();
    }
    _episodeFocusNodes.clear();
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
        focusNode: _rootFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          // Khi đang hiển thị thẻ Lỗi hoặc đếm ngược Tập tiếp theo (OSD đang ẩn),
          // nhường D-pad & OK cho các nút TvFocusableCard trên overlay đó nhận sự kiện!
          if (_hasError || (_nextCountdownSeconds > 0 && !_showControls)) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                    event.logicalKey == LogicalKeyboardKey.arrowRight ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
              return KeyEventResult.ignored;
            }
          }

          final key = event.logicalKey;
          final String debugName = key.debugName?.toLowerCase() ?? '';

          // 1. Physical Play key on remote
          final bool isPlayKey = key == LogicalKeyboardKey.mediaPlay ||
              (debugName.contains('mediaplay') && !debugName.contains('pause'));

          // 2. Physical Pause / Stop key on remote
          final bool isPauseKey = key == LogicalKeyboardKey.mediaPause ||
              key == LogicalKeyboardKey.mediaStop ||
              ((debugName.contains('mediapause') || debugName.contains('mediastop')) && !debugName.contains('play'));

          // 3. Play / Pause toggle key (Space, mediaPlayPause, or desktop Key K)
          final bool isPlayPauseToggle = key == LogicalKeyboardKey.mediaPlayPause ||
              key == LogicalKeyboardKey.space ||
              debugName.contains('playpause') ||
              debugName.contains('play_pause') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyK);

          // 4. Physical Fast Forward (Tua tới) key on remote
          final bool isFwdKey = key == LogicalKeyboardKey.mediaFastForward ||
              key == LogicalKeyboardKey.mediaSkipForward ||
              key == LogicalKeyboardKey.mediaStepForward ||
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
              debugName.contains('rewind') ||
              debugName.contains('skipbackward') ||
              debugName.contains('skip_backward') ||
              debugName.contains('stepbackward') ||
              debugName.contains('step_backward') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyJ);

          // 6. Track navigation (Previous / Next Track)
          final bool isPrevTrack = key == LogicalKeyboardKey.mediaTrackPrevious ||
              debugName.contains('trackprevious') ||
              debugName.contains('track_previous') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyP);
          final bool isNextTrack = key == LogicalKeyboardKey.mediaTrackNext ||
              debugName.contains('tracknext') ||
              debugName.contains('track_next') ||
              (_isMacOrDesktop && key == LogicalKeyboardKey.keyN);

          // 7. D-pad Navigation Left / Right
          final bool isLeft = key == LogicalKeyboardKey.arrowLeft;
          final bool isRight = key == LogicalKeyboardKey.arrowRight;

          // Trên Android TV / iOS, phím Back được xử lý duy nhất qua PopScope.onPopInvoked
          // để tránh lỗi 1 lần bấm Back kích hoạt kép (KeyDownEvent + onBackPressed lúc nhả phím)
          final bool isBack = _isMacOrDesktop &&
              (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace);

          if (event is KeyDownEvent) {
            if (isBack) {
              _handleBackAction();
              return KeyEventResult.handled;
            }

            if (_isScreenLocked) {
              return KeyEventResult.ignored;
            }

            // Keyboard Shortcuts for macOS & Desktop (Arrow Left/Right to Seek, Arrow Up/Down for Volume)
            if (_isMacOrDesktop && !_showStreamSelector && !_showEpisodeSelector) {
              if (isLeft) {
                if (widget.isLive) {
                  _showBriefPlaybackHud('CHANNEL', 'Đang phát trực tiếp');
                } else {
                  _seekDirectOffset(-10);
                }
                return KeyEventResult.handled;
              }
              if (isRight) {
                if (widget.isLive) {
                  _showBriefPlaybackHud('CHANNEL', 'Đang phát trực tiếp');
                } else {
                  _seekDirectOffset(10);
                }
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowUp) {
                _changeVolumeBy(0.05);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowDown) {
                _changeVolumeBy(-0.05);
                return KeyEventResult.handled;
              }
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
              if (_showStreamSelector || _showEpisodeSelector) {
                setState(() {
                  _showStreamSelector = false;
                  _showEpisodeSelector = false;
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
              if (_showStreamSelector || _showEpisodeSelector) {
                setState(() {
                  _showStreamSelector = false;
                  _showEpisodeSelector = false;
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
              _triggerEpisodeCallback(widget.onPrevious);
              return KeyEventResult.handled;
            }
            if (isNextTrack && widget.onNext != null) {
              _triggerEpisodeCallback(widget.onNext);
              return KeyEventResult.handled;
            }

            // Select / Enter (Chuẩn YouTube Android TV: bấm Select sẽ tự động nhảy xuống hàng nút điều khiển bên dưới)
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.gameButtonA) {
              if (!_showControls) {
                _lastFocusedOnSeekBar = false;
                _showControlsBriefly(focusControls: true);
                return KeyEventResult.handled;
              }
              if (_showStreamSelector || _showEpisodeSelector) {
                return KeyEventResult.ignored;
              }
              final anyControlButtonFocused = _getActiveControlNodes().any((n) => n.hasFocus) ||
                  _backButtonFocusNode.hasFocus ||
                  (_isTouchMobile && (_rotateFocusNode.hasFocus || _lockFocusNode.hasFocus));
              if (!anyControlButtonFocused) {
                if (_isHoldingSeek) {
                  _commitPendingSeek();
                }
                _lastFocusedOnSeekBar = false;
                _playPauseFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // Khi đã focus vào một nút TvFocusableCard ở dưới, để nút đó xử lý sự kiện bấm
              return KeyEventResult.ignored;
            }

            // Left navigation / seek
            if (isLeft) {
              if (_showStreamSelector || _showEpisodeSelector) {
                _startHideControlsTimer();
                return KeyEventResult.ignored;
              }
              if (_isTouchMobile) {
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
              }
              final controlNodes = _getActiveControlNodes();
              final currentIdx = controlNodes.indexWhere((n) => n.hasFocus);
              final bool anyButtonFocused = currentIdx != -1 ||
                  _backButtonFocusNode.hasFocus ||
                  (_isTouchMobile && (_rotateFocusNode.hasFocus || _lockFocusNode.hasFocus));

              if (!_showControls || _seekBarFocusNode.hasFocus || !anyButtonFocused) {
                if (widget.isLive) {
                  _showControlsBriefly(focusControls: true);
                  return KeyEventResult.handled;
                }
                _lastFocusedOnSeekBar = true;
                if (_isHoldingSeek && _holdSeekDirection == -1) {
                  _handleRemoteSeekRepeat(-1);
                } else {
                  _handleRemoteSeekStart(-1);
                }
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // Explicitly navigate between control buttons in the bottom bar
              if (currentIdx > 0) {
                controlNodes[currentIdx - 1].requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              _startHideControlsTimer();
              return KeyEventResult.handled;
            }

            // Right navigation / seek
            if (isRight) {
              if (_showStreamSelector || _showEpisodeSelector) {
                _startHideControlsTimer();
                return KeyEventResult.ignored;
              }
              if (_isTouchMobile) {
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
              }
              final controlNodes = _getActiveControlNodes();
              final currentIdx = controlNodes.indexWhere((n) => n.hasFocus);
              final bool anyButtonFocused = currentIdx != -1 ||
                  _backButtonFocusNode.hasFocus ||
                  (_isTouchMobile && (_rotateFocusNode.hasFocus || _lockFocusNode.hasFocus));

              if (!_showControls || _seekBarFocusNode.hasFocus || !anyButtonFocused) {
                if (widget.isLive) {
                  _showControlsBriefly(focusControls: true);
                  return KeyEventResult.handled;
                }
                _lastFocusedOnSeekBar = true;
                if (_isHoldingSeek && _holdSeekDirection == 1) {
                  _handleRemoteSeekRepeat(1);
                } else {
                  _handleRemoteSeekStart(1);
                }
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // Explicitly navigate between control buttons in the bottom bar
              if (currentIdx != -1 && currentIdx + 1 < controlNodes.length) {
                controlNodes[currentIdx + 1].requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              _startHideControlsTimer();
              return KeyEventResult.handled;
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

            // Phím CH+ / CH- chuyên dụng trên remote Android TV để chuyển kênh IPTV / luồng trực tiếp tức thì
            if (key == LogicalKeyboardKey.channelUp) {
              if (widget.isLive && _effectiveChannels.length > 1) {
                _switchChannelDelta(1);
                return KeyEventResult.handled;
              }
            }
            if (key == LogicalKeyboardKey.channelDown) {
              if (widget.isLive && _effectiveChannels.length > 1) {
                _switchChannelDelta(-1);
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
                _showControlsBriefly(focusControls: true);
                return KeyEventResult.handled;
              }
              if (_showStreamSelector || _showEpisodeSelector) {
                _startHideControlsTimer();
                return KeyEventResult.ignored;
              }
              if (_seekBarFocusNode.hasFocus) {
                _backButtonFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              if (_backButtonFocusNode.hasFocus || (_isTouchMobile && (_rotateFocusNode.hasFocus || _lockFocusNode.hasFocus))) {
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // For Live (Football), there is no seekbar -> Up goes directly to back button
              if (widget.isLive) {
                _backButtonFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              _lastFocusedOnSeekBar = true;
              _seekBarFocusNode.requestFocus();
              _startHideControlsTimer();
              return KeyEventResult.handled;
            }
            if (isDown) {
              if (!_showControls) {
                _showControlsBriefly(focusControls: true);
                return KeyEventResult.handled;
              }
              if (_showStreamSelector || _showEpisodeSelector) {
                _startHideControlsTimer();
                return KeyEventResult.ignored;
              }
              if (_backButtonFocusNode.hasFocus || (_isTouchMobile && (_rotateFocusNode.hasFocus || _lockFocusNode.hasFocus))) {
                if (widget.isLive) {
                  _playPauseFocusNode.requestFocus();
                } else {
                  _lastFocusedOnSeekBar = true;
                  _seekBarFocusNode.requestFocus();
                }
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              final anyControlFocused = _getActiveControlNodes().any((n) => n.hasFocus);
              if (_seekBarFocusNode.hasFocus || !anyControlFocused) {
                _lastFocusedOnSeekBar = false;
                _playPauseFocusNode.requestFocus();
                _startHideControlsTimer();
                return KeyEventResult.handled;
              }
              // From bottom control buttons -> Down to dismiss controls!
              setState(() {
                _showControls = false;
              });
              _hideControlsTimer?.cancel();
              _rootFocusNode.requestFocus();
              return KeyEventResult.handled;
            }
          } else if (event is KeyRepeatEvent) {
            if (_isScreenLocked) return KeyEventResult.ignored;
            if (_isMacOrDesktop && !_showStreamSelector && !_showEpisodeSelector) {
              if (isLeft) {
                if (!widget.isLive) _seekDirectOffset(-10);
                return KeyEventResult.handled;
              }
              if (isRight) {
                if (!widget.isLive) _seekDirectOffset(10);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowUp) {
                _changeVolumeBy(0.05);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.arrowDown) {
                _changeVolumeBy(-0.05);
                return KeyEventResult.handled;
              }
            }
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
            if (isLeft && (_isHoldingSeek || !_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekRepeat(-1);
              return KeyEventResult.handled;
            }
            if (isRight && (_isHoldingSeek || !_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekRepeat(1);
              return KeyEventResult.handled;
            }
          } else if (event is KeyUpEvent) {
            if (_isScreenLocked) return KeyEventResult.ignored;
            if (_isMacOrDesktop && !_showStreamSelector && !_showEpisodeSelector) {
              if (isLeft || isRight || key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
                return KeyEventResult.handled;
              }
            }
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
            if (isLeft && (_isHoldingSeek || !_showControls || _seekBarFocusNode.hasFocus)) {
              _handleRemoteSeekEnd(-1);
              return KeyEventResult.handled;
            }
            if (isRight && (_isHoldingSeek || !_showControls || _seekBarFocusNode.hasFocus)) {
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
              onHorizontalDragStart: (_isTouchMobile && !_isScreenLocked) ? _onHorizontalDragStart : null,
              onHorizontalDragUpdate: (_isTouchMobile && !_isScreenLocked) ? _onHorizontalDragUpdate : null,
              onHorizontalDragEnd: (_isTouchMobile && !_isScreenLocked) ? _onHorizontalDragEnd : null,
              onVerticalDragStart: (_isTouchMobile && !_isScreenLocked) ? _onVerticalDragStart : null,
              onVerticalDragUpdate: (_isTouchMobile && !_isScreenLocked) ? _onVerticalDragUpdate : null,
              onVerticalDragEnd: (_isTouchMobile && !_isScreenLocked) ? _onVerticalDragEnd : null,
              onLongPressStart: (_isTouchMobile && !_isScreenLocked) ? _onLongPressStart : null,
              onLongPressMoveUpdate: (_isTouchMobile && !_isScreenLocked) ? _onLongPressMoveUpdate : null,
              onLongPressEnd: (_isTouchMobile && !_isScreenLocked) ? _onLongPressEnd : null,
              onLongPressCancel: (_isTouchMobile && !_isScreenLocked) ? _onLongPressCancel : null,
              behavior: HitTestBehavior.opaque,
              child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. VIDEO CANVAS (Supports Fit / Fill / 16:9 / 4:3 aspect modes)
              if (_isInitialized && _controller != null)
                Builder(
                  builder: (_) {
                    final nativeRatio = _controller!.value.aspectRatio > 0 ? _controller!.value.aspectRatio : 16 / 9;
                    if (_aspectModeIndex == 1) {
                      // Lấp đầy (Cover / Fill)
                      return SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: _controller!.value.size.width > 0 ? _controller!.value.size.width : 1280,
                            height: _controller!.value.size.height > 0 ? _controller!.value.size.height : 720,
                            child: VideoPlayer(_controller!),
                          ),
                        ),
                      );
                    }
                    final double ratio = _aspectModeIndex == 2
                        ? 16 / 9
                        : (_aspectModeIndex == 3 ? 4 / 3 : nativeRatio);
                    return Center(
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: VideoPlayer(_controller!),
                      ),
                    );
                  },
                )
              else if (_hasError)
                Center(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      constraints: const BoxConstraints(maxWidth: 520),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
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
                                      color: isCurrent ? const Color(0xFFEF4444).withOpacity(0.3) : const Color(0xFF262626),
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
                            focusNode: _errorRetryFocusNode,
                            autoFocus: true,
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
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF38BDF8)),
                      const SizedBox(height: 16),
                      Text(
                        _isReconnecting
                            ? 'Đang kết nối lại ($_reconnectAttempts/$_maxLiveReconnects)...'
                            : 'Đang tải luồng phát...',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),

              // 1b. SOFTWARE BRIGHTNESS DIMMING OVERLAY (Mobile Left-half vertical drag)
              if (_isTouchMobile && _softwareBrightness < 0.99)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: Colors.black.withOpacity((1.0 - _softwareBrightness).clamp(0.0, 0.75)),
                    ),
                  ),
                ),

              // 2. DOUBLE-TAP SEEK ZONES (iOS & Android Phone - Left 50% & Right 50% screen)
              if (_isTouchMobile) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: screenSize.width * 0.5,
                  child: GestureDetector(
                    onDoubleTap: () {
                      if (_isScreenLocked) return;
                      _onDoubleTapSide(false);
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: screenSize.width * 0.5,
                  child: GestureDetector(
                    onDoubleTap: () {
                      if (_isScreenLocked) return;
                      _onDoubleTapSide(true);
                    },
                    behavior: HitTestBehavior.translucent,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],

              // 3. DOUBLE-TAP RIPPLE INDICATORS (YouTube-style curved side overlay)
              if (_isTouchMobile && _showDoubleTapLeft)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: screenSize.width * 0.45,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.elliptical(screenSize.width * 0.45, screenSize.height * 0.5),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 44),
                            const SizedBox(height: 8),
                            Text(
                              '-${_doubleTapAccumulatedSeconds}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isTouchMobile && _showDoubleTapRight)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: screenSize.width * 0.45,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.elliptical(screenSize.width * 0.45, screenSize.height * 0.5),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 44),
                            const SizedBox(height: 8),
                            Text(
                              '+${_doubleTapAccumulatedSeconds}s',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // 3b. BUFFERING HUD INDICATOR (Khi video đang load bộ đệm giữa chừng)
              if (_isInitialized && _controller != null && _controller!.value.isBuffering)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withOpacity(0.15),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Đang nạp bộ đệm...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_controller!.value.duration.inMilliseconds > 0 && _videoBufferedPosition.inMilliseconds > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Buffer: ${((_videoBufferedPosition.inMilliseconds / _controller!.value.duration.inMilliseconds) * 100).clamp(0, 100).toInt()}%',
                            style: TextStyle(
                              color: const Color(0xFF38BDF8).withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
                                  onTap: _exitPlayer,
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
                                                                                      : (_hudIcon == 'BRIGHTNESS'
                                                                                          ? Icons.brightness_6_rounded
                                                                                          : (_hudIcon == 'SPEED'
                                                                                              ? Icons.speed_rounded
                                                                                              : (_hudIcon == 'ASPECT'
                                                                                                  ? Icons.aspect_ratio_rounded
                                                                                                  : Icons.volume_up_rounded)))))))))))),
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
                              // Rotate Screen & Lock Touch Screen Buttons (iOS & Android Phone)
                              if (_isTouchMobile) ...[
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
                              ],
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
                                            focusNode: _volumeSliderFocusNode,
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

                      // Center: Tap empty area to dismiss controls immediately, or double tap to seek 10s
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () {
                                  if (_isScreenLocked) return;
                                  _toggleControls();
                                },
                                onDoubleTap: _isTouchMobile && !_isScreenLocked
                                    ? () => _onDoubleTapSide(false)
                                    : null,
                                child: const SizedBox.expand(),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () {
                                  if (_isScreenLocked) return;
                                  _toggleControls();
                                },
                                onDoubleTap: _isTouchMobile && !_isScreenLocked
                                    ? () => _onDoubleTapSide(true)
                                    : null,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      ),

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
                              if (!widget.isLive && _isInitialized && _controller != null) ...[
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
                                    child: Builder(
                                      builder: (_) {
                                        final dur = _controller!.value.duration;
                                        final maxSec = dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
                                        final curPos = _isHoldingSeek ? _pendingSeekPosition : _controller!.value.position;
                                        return Row(
                                          children: [
                                            Text(
                                              _formatDuration(curPos),
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
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    // 1. Buffered Track Bar
                                                    Padding(
                                                      padding: EdgeInsets.symmetric(horizontal: _isTouchMobile ? 8.5 : 6.5),
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: LinearProgressIndicator(
                                                          value: dur.inMilliseconds > 0
                                                              ? (_videoBufferedPosition.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                                              : 0.0,
                                                          minHeight: _isTouchMobile ? 5.0 : 4.0,
                                                          backgroundColor: Colors.white24,
                                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.4)),
                                                        ),
                                                      ),
                                                    ),
                                                    // 2. Active Slider
                                                    SliderTheme(
                                                      data: SliderTheme.of(context).copyWith(
                                                        activeTrackColor: const Color(0xFF38BDF8),
                                                        inactiveTrackColor: Colors.transparent,
                                                        thumbColor: const Color(0xFF38BDF8),
                                                        overlayColor: const Color(0xFF38BDF8).withOpacity(0.2),
                                                        thumbShape: RoundSliderThumbShape(enabledThumbRadius: _isTouchMobile ? 8.5 : 6.5),
                                                        trackHeight: _isTouchMobile ? 5.0 : 4.0,
                                                      ),
                                                      child: Slider(
                                                        focusNode: _progressSliderFocusNode,
                                                        value: curPos.inSeconds.toDouble().clamp(0.0, maxSec),
                                                        max: maxSec,
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
                                                          final ctrl = _controller;
                                                          if (ctrl == null) {
                                                            setState(() => _isHoldingSeek = false);
                                                            return;
                                                          }
                                                          final target = Duration(seconds: val.toInt());
                                                          ctrl.seekTo(target).whenComplete(() {
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
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatDuration(dur),
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))],
                                              ),
                                            ),
                                            if (!widget.isLive && dur.inMilliseconds > 0 && _videoBufferedPosition.inMilliseconds > 0) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                '• Đã nạp: ${_formatDuration(_videoBufferedPosition)} (${((_videoBufferedPosition.inMilliseconds / dur.inMilliseconds) * 100).round()}%)',
                                                style: TextStyle(
                                                  color: const Color(0xFF38BDF8).withOpacity(0.85),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))],
                                                ),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],

                              // Playback Controls Row (Cuộn ngang an toàn cho màn hình điện thoại dọc, căn giữa trên TV/iPad)
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (widget.onPrevious != null) ...[
                                      TvFocusableCard(
                                        focusNode: _prevFocusNode,
                                        onTap: () => _triggerEpisodeCallback(widget.onPrevious),
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
                                        (_controller?.value.isPlaying ?? false) ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                        color: const Color(0xFF38BDF8),
                                        size: 46,
                                      ),
                                    ),
                                  ),
                                  if (!widget.isLive) ...[
                                    const SizedBox(width: 12),
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
                                    const SizedBox(width: 10),
                                    TvFocusableCard(
                                      focusNode: _skipIntroFocusNode,
                                      onTap: () => _seekDirectOffset(85, customHudText: 'Bỏ qua Intro +85s'),
                                      scale: 1.08,
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(color: Colors.white24, width: 0.8),
                                        ),
                                        child: const Text(
                                          '+85s',
                                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    TvFocusableCard(
                                      focusNode: _speedButtonFocusNode,
                                      onTap: _cyclePlaybackSpeed,
                                      scale: 1.08,
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: _playbackSpeed != 1.0
                                              ? const Color(0xFF0284C7)
                                              : Colors.white.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: _playbackSpeed != 1.0 ? const Color(0xFF38BDF8) : Colors.white24,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          '${_playbackSpeed}x',
                                          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 10),
                                  TvFocusableCard(
                                    focusNode: _aspectButtonFocusNode,
                                    onTap: _cycleAspectMode,
                                    scale: 1.08,
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: _aspectModeIndex != 0
                                            ? const Color(0xFF0284C7)
                                            : Colors.white.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: _aspectModeIndex != 0 ? const Color(0xFF38BDF8) : Colors.white24,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            _aspectModeLabels[_aspectModeIndex],
                                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (widget.onNext != null) ...[
                                    const SizedBox(width: 12),
                                    TvFocusableCard(
                                      focusNode: _nextFocusNode,
                                      onTap: () => _triggerEpisodeCallback(widget.onNext),
                                      scale: 1.08,
                                      borderRadius: BorderRadius.circular(18),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE50914).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: const Color(0xFFE50914).withOpacity(0.6),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.skip_next_rounded, color: Colors.white, size: 18),
                                            const SizedBox(width: 5),
                                            Text(
                                              widget.episode > 0 ? 'Next Tập ${widget.episode + 1}' : 'Next (Tập tiếp)',
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
                                  if (widget.episodes != null && widget.episodes!.isNotEmpty && widget.onSelectEpisode != null) ...[
                                    const SizedBox(width: 14),
                                    TvFocusableCard(
                                      focusNode: _episodesButtonFocusNode,
                                      onTap: () {
                                        setState(() {
                                          _showEpisodeSelector = !_showEpisodeSelector;
                                          if (_showEpisodeSelector) {
                                            _showStreamSelector = false;
                                          }
                                        });
                                        if (_showEpisodeSelector) {
                                          _initEpisodeFocusNodes();
                                          _startHideControlsTimer();
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            _focusCurrentEpisode();
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
                                          color: _showEpisodeSelector
                                              ? const Color(0xFF0284C7)
                                              : Colors.white.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(18),
                                          border: Border.all(
                                            color: _showEpisodeSelector ? const Color(0xFF38BDF8) : Colors.white24,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.video_library_rounded, color: Colors.white, size: 15),
                                            SizedBox(width: 6),
                                            Text(
                                              'Chọn tập',
                                              style: TextStyle(
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
                                  if (_effectiveChannels.isNotEmpty) ...[
                                    const SizedBox(width: 14),
                                    TvFocusableCard(
                                      focusNode: _channelsButtonFocusNode,
                                      onTap: () {
                                        setState(() {
                                          _showStreamSelector = !_showStreamSelector;
                                          if (_showStreamSelector) {
                                            _showEpisodeSelector = false;
                                          }
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
                              ),
                              if (!_isTouchMobile && !_isMacOrDesktop) ...[
                                const SizedBox(height: 6),
                                Text(
                                  widget.isLive
                                      ? '▲▼ Điều khiển  •  OK Phát/Dừng  •  CH± Đổi kênh  •  Back Ẩn/Thoát'
                                      : '◀▶ Tua video  •  ▲▼ Điều khiển  •  OK Phát/Dừng  •  Back Ẩn/Thoát',
                                  style: TextStyle(color: Colors.white.withOpacity(0.48), fontSize: 10.5),
                                  textAlign: TextAlign.center,
                                ),
                              ],
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
                  right: screenSize.width < 460 ? 16 : 28,
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
                      width: screenSize.width < 460 ? screenSize.width - 32 : 380,
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

              // 5.6 VERTICAL EPISODE SELECTOR PANEL (DANH SÁCH TẬP PHIM CHO SERIES)
              if (_showEpisodeSelector && widget.episodes != null && widget.episodes!.isNotEmpty)
                Positioned(
                  bottom: 96,
                  right: screenSize.width < 500 ? 16 : 28,
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
                      width: screenSize.width < 500 ? screenSize.width - 32 : 440,
                      constraints: const BoxConstraints(maxHeight: 300),
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
                              Row(
                                children: [
                                  const Icon(Icons.video_library_rounded, color: Color(0xFF38BDF8), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'DANH SÁCH TẬP (${widget.episodes!.length} TẬP)',
                                    style: const TextStyle(
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
                                    _showEpisodeSelector = false;
                                  });
                                  _episodesButtonFocusNode.requestFocus();
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
                          const SizedBox(height: 12),
                          Flexible(
                            child: GridView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 80,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                mainAxisExtent: 38,
                              ),
                              itemCount: widget.episodes!.length,
                              itemBuilder: (context, index) {
                                final ep = widget.episodes![index];
                                final bool isSelected = ep.episode == widget.episode ||
                                    (widget.currentEpisodeIndex >= 0 && index == widget.currentEpisodeIndex);
                                final node = index < _episodeFocusNodes.length ? _episodeFocusNodes[index] : null;
                                return Focus(
                                  onKeyEvent: (focusNode, event) {
                                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft && index % 5 == 0) {
                                      setState(() {
                                        _showEpisodeSelector = false;
                                      });
                                      _episodesButtonFocusNode.requestFocus();
                                      _startHideControlsTimer();
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TvFocusableCard(
                                    focusNode: node,
                                    onTap: () {
                                      setState(() {
                                        _showEpisodeSelector = false;
                                      });
                                      widget.onSelectEpisode?.call(index);
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF0284C7)
                                            : Colors.white.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected ? const Color(0xFF38BDF8) : Colors.white12,
                                          width: isSelected ? 1.5 : 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        'Tập ${ep.episode}',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white70,
                                          fontSize: 12,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        ),
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
                          focusNode: _countdownPlayFocusNode,
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
                          focusNode: _countdownCancelFocusNode,
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

              // 5. FLOATING UNLOCK BUTTON (iOS & Android Phone)
              if (_isTouchMobile && _isScreenLocked)
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

              // 6. TELEGRAM-STYLE FAST FORWARD HUD (2x -> 3x - iOS & Android Phone)
              if (_isTouchMobile && _isHoldSpeeding)
                Positioned(
                  top: 24,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xE60F172A),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _currentHoldSpeed == 3.0 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_currentHoldSpeed == 3.0 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8)).withOpacity(0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _currentHoldSpeed == 3.0 ? Icons.bolt_rounded : Icons.fast_forward_rounded,
                            color: _currentHoldSpeed == 3.0 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentHoldSpeed == 3.0 ? 'Tốc độ 3X' : 'Tốc độ 2X',
                            style: TextStyle(
                              color: _currentHoldSpeed == 3.0 ? const Color(0xFFFBBF24) : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _currentHoldSpeed == 3.0 ? const Color(0x33F59E0B) : const Color(0x3338BDF8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _currentHoldSpeed == 3.0 ? '⚡ Cực nhanh' : '👉 Vuốt sang phải để lên 3X',
                              style: TextStyle(
                                color: _currentHoldSpeed == 3.0 ? const Color(0xFFFDE68A) : const Color(0xFFBAE6FD),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
