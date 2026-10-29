import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NetflixScrollableRow extends StatefulWidget {
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemSpacing;
  final EdgeInsets padding;
  final double scrollDelta;

  const NetflixScrollableRow({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.itemSpacing = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.scrollDelta = 460,
  });

  @override
  State<NetflixScrollableRow> createState() => _NetflixScrollableRowState();
}

class _NetflixScrollableRowState extends State<NetflixScrollableRow> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isRowHovered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(covariant NetflixScrollableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final canLeft = _scrollController.offset > 20;
    final canRight = _scrollController.position.maxScrollExtent > 20 &&
        _scrollController.offset < (_scrollController.position.maxScrollExtent - 20);

    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLeft = _isRowHovered && _canScrollLeft;
    final showRight = _isRowHovered && _canScrollRight && widget.itemCount > 1;

    return MouseRegion(
      onEnter: (_) => setState(() => _isRowHovered = true),
      onExit: (_) => setState(() => _isRowHovered = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Horizontal ListView with metrics listener
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                final metrics = notification.metrics;
                final canLeft = metrics.pixels > 20;
                final canRight = metrics.maxScrollExtent > 20 &&
                    metrics.pixels < (metrics.maxScrollExtent - 20);
                if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() {
                        _canScrollLeft = canLeft;
                        _canScrollRight = canRight;
                      });
                    }
                  });
                }
                return false;
              },
              child: ListView.separated(
                controller: _scrollController,
                padding: widget.padding,
                scrollDirection: Axis.horizontal,
                cacheExtent: 3500,
                itemCount: widget.itemCount,
                separatorBuilder: (_, __) => SizedBox(width: widget.itemSpacing),
                itemBuilder: (context, idx) {
                  final child = widget.itemBuilder(context, idx);
                  return Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: (node, event) {
                      final isDownOrRepeat = event is KeyDownEvent || event is KeyRepeatEvent;
                      if (!isDownOrRepeat) return KeyEventResult.ignored;

                      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                        if (idx >= widget.itemCount - 1) {
                          // Đã ở phần tử cuối cùng của hàng ngang:
                          // Chặn tuyệt đối không cho focus thoát khỏi hàng và nhảy xuống hàng dưới làm trôi màn hình!
                          return KeyEventResult.handled;
                        }
                      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                        if (idx == 0) {
                          // Ở đầu hàng ngang: Cho phép sự kiện nổi lên để NetflixLayout bắt và nhảy sang Sidebar
                          return KeyEventResult.ignored;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: child,
                  );
                },
              ),
            ),

            // 2. Left Arrow Button (Mặc định ẩn, chỉ hiện mượt khi hover chuột vào hàng)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: showLeft ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !showLeft,
                    child: _NetflixArrowButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: () => _scrollBy(-widget.scrollDelta),
                      isLeft: true,
                    ),
                  ),
                ),
              ),
            ),

            // 3. Right Arrow Button (Mặc định ẩn, chỉ hiện mượt khi hover chuột vào hàng)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: showRight ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !showRight,
                    child: _NetflixArrowButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: () => _scrollBy(widget.scrollDelta),
                      isLeft: false,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetflixArrowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isLeft;

  const _NetflixArrowButton({
    required this.icon,
    required this.onTap,
    required this.isLeft,
  });

  @override
  State<_NetflixArrowButton> createState() => _NetflixArrowButtonState();
}

class _NetflixArrowButtonState extends State<_NetflixArrowButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : (_isHovered ? 1.12 : 1.0),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 36,
            height: 68,
            decoration: BoxDecoration(
              color: const Color(0xFFE50914), // Netflix Red
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isHovered ? 0.7 : 0.5),
                  blurRadius: _isHovered ? 12 : 8,
                  offset: Offset(widget.isLeft ? 2 : -2, 2),
                ),
                if (_isHovered)
                  BoxShadow(
                    color: const Color(0xFFE50914).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 0),
                  ),
              ],
            ),
            child: Center(
              child: Icon(
                widget.icon,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
