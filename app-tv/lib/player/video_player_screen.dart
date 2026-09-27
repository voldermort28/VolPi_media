import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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

  @override
  void initState() {
    super.initState();
    _currentStreamUrl = widget.streamUrl;
    _currentTitle = widget.title;
    _currentHeaders = widget.headers;

    WakelockPlus.enable();
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

  void _switchChannel(StreamChannel channel) {
    if (_currentStreamUrl == channel.url) return;
    _controller.dispose();
    setState(() {
      _currentStreamUrl = channel.url;
      _currentTitle = channel.title;
      _currentHeaders = channel.headers;
    });
    _initPlayer();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
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

  void _seekRelative(int seconds) {
    if (!_isInitialized || widget.isLive) return;
    final current = _controller.value.position;
    final target = current + Duration(seconds: seconds);
    _controller.seekTo(target);
    _showControls = true;
    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.mediaPlayPause) {
            _togglePlayPause();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
            _seekRelative(-10);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
            _seekRelative(10);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
            setState(() {
              _showControls = true;
            });
            _startHideControlsTimer();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // VIDEO CANVAS
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
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
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

              // OSD OVERLAY CONTROLS
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

                          // Center Play/Pause Indicator
                          IconButton(
                            iconSize: 64,
                            icon: Icon(
                              _controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: const Color(0xFF38BDF8),
                            ),
                            onPressed: _togglePlayPause,
                          ),

                          // Bottom Bar with Channel Switcher
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Column(
                              children: [
                                // Available Channels / BLV Switcher row
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
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

                                // Progress Bar for VOD
                                if (!widget.isLive && _isInitialized)
                                  VideoProgressIndicator(
                                    _controller,
                                    allowScrubbing: true,
                                    colors: const VideoProgressColors(
                                      playedColor: Color(0xFF38BDF8),
                                      bufferedColor: Colors.white24,
                                      backgroundColor: Colors.white10,
                                    ),
                                  ),
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
