import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../models/match_model.dart';
import '../widgets/tv_focusable_card.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String subtitle;
  final Map<String, String> headers;
  final List<StreamChannel>? availableChannels;
  final bool isLive;

  const VideoPlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.subtitle = '',
    this.headers = const {},
    this.availableChannels,
    this.isLive = false,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
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

  @override
  void initState() {
    super.initState();
    _currentStreamUrl = widget.streamUrl;
    _currentTitle = widget.title;
    _currentHeaders = widget.headers;

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
      _controller.play();

      _controller.addListener(_videoListener);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _startHideControlsTimer();
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
    if (mounted && _isInitialized) {
      setState(() {});
    }
  }

  void _switchChannel(StreamChannel channel) {
    if (_currentStreamUrl == channel.url) return;
    _controller.removeListener(_videoListener);
    _controller.dispose();
    setState(() {
      _currentStreamUrl = channel.url;
      _currentTitle = channel.title;
      _currentHeaders = channel.headers;
    });
    _initPlayer();
  }

  void _switchChannelDelta(int delta) {
    final channels = widget.availableChannels;
    if (channels == null || channels.isEmpty) return;
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
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying && !_isDragging) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _showControlsBriefly() {
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
        _hideControlsTimer?.cancel();
      } else {
        _controller.play();
        _startHideControlsTimer();
      }
    });
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
      if (mounted && !_isHoldingSeek) {
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

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _hudFadeTimer?.cancel();
    _doubleTapTimer?.cancel();
    _commitSeekTimer?.cancel();
    _controller.removeListener(_videoListener);
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final key = event.logicalKey;
        final bool isLeft = key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.mediaRewind ||
            key == LogicalKeyboardKey.mediaTrackPrevious;
        final bool isRight = key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.mediaFastForward ||
            key == LogicalKeyboardKey.mediaTrackNext;

        if (event is KeyDownEvent) {
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.mediaPlayPause) {
            _togglePlayPause();
            return KeyEventResult.handled;
          }
          if (isLeft) {
            if (_isHoldingSeek && _holdSeekDirection == -1) {
              _handleRemoteSeekRepeat(-1);
            } else {
              _handleRemoteSeekStart(-1);
            }
            return KeyEventResult.handled;
          }
          if (isRight) {
            if (_isHoldingSeek && _holdSeekDirection == 1) {
              _handleRemoteSeekRepeat(1);
            } else {
              _handleRemoteSeekStart(1);
            }
            return KeyEventResult.handled;
          }
          final bool isUp = key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.channelUp ||
              key == LogicalKeyboardKey.pageUp;
          final bool isDown = key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.channelDown ||
              key == LogicalKeyboardKey.pageDown;

          if (isUp) {
            if (widget.isLive && widget.availableChannels != null && widget.availableChannels!.length > 1) {
              _switchChannelDelta(-1);
            } else {
              _showControlsBriefly();
            }
            return KeyEventResult.handled;
          }
          if (isDown) {
            if (widget.isLive && widget.availableChannels != null && widget.availableChannels!.length > 1) {
              _switchChannelDelta(1);
            } else {
              _showControlsBriefly();
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        } else if (event is KeyRepeatEvent) {
          if (isLeft) {
            _handleRemoteSeekRepeat(-1);
            return KeyEventResult.handled;
          }
          if (isRight) {
            _handleRemoteSeekRepeat(1);
            return KeyEventResult.handled;
          }
        } else if (event is KeyUpEvent) {
          if (isLeft) {
            _handleRemoteSeekEnd(-1);
            return KeyEventResult.handled;
          }
          if (isRight) {
            _handleRemoteSeekEnd(1);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          onHorizontalDragStart: _onHorizontalDragStart,
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: _onHorizontalDragEnd,
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
                  onDoubleTap: () => _onDoubleTapSide(false),
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
                  onDoubleTap: () => _onDoubleTapSide(true),
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

              // 4. SWIPE SEEK HUD OVERLAY (Center Indicator)
              if (_hudIcon != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _hudIcon == 'CHANNEL'
                                  ? Icons.live_tv_rounded
                                  : (_hudIcon == 'FORWARD' ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded),
                              color: const Color(0xFF38BDF8),
                              size: 44,
                            ),
                            if (_hudSpeedBadge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                                ),
                                child: Text(
                                  _hudSpeedBadge!,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _hudText ?? '',
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_hudIcon != 'CHANNEL') ...[
                          const SizedBox(height: 4),
                          Text(
                            '${_formatDuration(_dragTargetPosition)} / ${_formatDuration(_controller.value.duration)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // 5. OSD OVERLAY CONTROLS (Top Bar, Center Play/Seek, Bottom Timeline)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black87, Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(
                              children: [
                                TvFocusableCard(
                                  onTap: () => Navigator.of(context).pop(),
                                  scale: 1.1,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    color: Colors.white12,
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
                                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (widget.subtitle.isNotEmpty)
                                        Text(
                                          widget.subtitle,
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w500),
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
                              ],
                            ),
                          ),

                          // Center Play/Seek Controls Row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!widget.isLive) ...[
                                TvFocusableCard(
                                  onTap: () => _seekRelative(-10),
                                  borderRadius: BorderRadius.circular(30),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    color: Colors.black38,
                                    child: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 36),
                                  ),
                                ),
                                const SizedBox(width: 32),
                              ],
                              TvFocusableCard(
                                onTap: _togglePlayPause,
                                borderRadius: BorderRadius.circular(40),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                    color: const Color(0xFF38BDF8),
                                    size: 68,
                                  ),
                                ),
                              ),
                              if (!widget.isLive) ...[
                                const SizedBox(width: 32),
                                TvFocusableCard(
                                  onTap: () => _seekRelative(10),
                                  borderRadius: BorderRadius.circular(30),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    color: Colors.black38,
                                    child: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 36),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          // Bottom Bar with Timeline & Channel/Variant Switcher
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Column(
                              children: [
                                // Available Channels / Streams Switcher Row
                                if (widget.availableChannels != null && widget.availableChannels!.length > 1) ...[
                                  SizedBox(
                                    height: 38,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: widget.availableChannels!.length,
                                      itemBuilder: (context, index) {
                                        final ch = widget.availableChannels![index];
                                        final bool isSelected = ch.url == _currentStreamUrl;
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: TvFocusableCard(
                                            onTap: () => _switchChannel(ch),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                              child: Text(
                                                ch.title,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : Colors.white70,
                                                  fontSize: 12,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],

                                // Progress Slider for VOD
                                if (!widget.isLive && _isInitialized) ...[
                                  Row(
                                    children: [
                                      Text(
                                        _formatDuration(_isHoldingSeek ? _pendingSeekPosition : _controller.value.position),
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            activeTrackColor: const Color(0xFF38BDF8),
                                            inactiveTrackColor: Colors.white24,
                                            thumbColor: const Color(0xFF38BDF8),
                                            overlayColor: const Color(0xFF38BDF8).withOpacity(0.2),
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                            trackHeight: 4.0,
                                          ),
                                          child: Slider(
                                            value: (_isHoldingSeek ? _pendingSeekPosition : _controller.value.position).inSeconds.toDouble().clamp(
                                                  0.0,
                                                  _controller.value.duration.inSeconds.toDouble(),
                                                ),
                                            max: _controller.value.duration.inSeconds.toDouble() > 0
                                                ? _controller.value.duration.inSeconds.toDouble()
                                                : 1.0,
                                            onChanged: (val) {
                                              _startHideControlsTimer();
                                              _controller.seekTo(Duration(seconds: val.toInt()));
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatDuration(_controller.value.duration),
                                        style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
