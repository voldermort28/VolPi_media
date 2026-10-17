import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvFocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final Color focusBorderColor;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;
  final bool autoFocus;

  const TvFocusableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 1.0,
    this.focusBorderColor = const Color(0xFF38BDF8), // Electric Sky Blue
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.focusNode,
    this.autoFocus = false,
  });

  @override
  State<TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<TvFocusableCard> with AutomaticKeepAliveClientMixin {
  late FocusNode _focusNode;
  bool _isFocused = false;
  Timer? _holdTimer;
  bool _holdFired = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(TvFocusableCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      if (oldWidget.focusNode == null) {
        _focusNode.dispose();
      }
      _focusNode = widget.focusNode ?? FocusNode();
      _focusNode.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) {
      final hasFocus = _focusNode.hasFocus;
      setState(() {
        _isFocused = hasFocus;
      });
      updateKeepAlive();

      if (hasFocus) {
        // Auto scroll viewport so the focused item is fully visible on TV screen
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusNode.hasFocus) {
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOutQuad,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autoFocus,
        onKeyEvent: (node, event) {
          final isSelect = event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA;

          if (!isSelect) return KeyEventResult.ignored;

          // Nếu widget không đăng ký onLongPress, giữ nguyên 100% logic cũ (bấm phát ăn ngay)
          if (widget.onLongPress == null) {
            if (event is KeyDownEvent) {
              widget.onTap();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          }

          // Xử lý giữ phím OK trên remote TV (600ms)
          if (event is KeyDownEvent && !_holdFired) {
            _holdTimer?.cancel();
            _holdTimer = Timer(const Duration(milliseconds: 600), () {
              _holdFired = true;
              widget.onLongPress!();
            });
            return KeyEventResult.handled;
          }

          if (event is KeyUpEvent) {
            _holdTimer?.cancel();
            if (!_holdFired) {
              // Thả phím trước 600ms -> Tap thông thường
              widget.onTap();
            }
            _holdFired = false;
            return KeyEventResult.handled;
          }

          if (event is KeyRepeatEvent) {
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () {
            _focusNode.requestFocus();
            widget.onTap();
          },
          onLongPress: widget.onLongPress != null
              ? () {
                  _focusNode.requestFocus();
                  widget.onLongPress!();
                }
              : null,
          child: AnimatedScale(
            scale: _isFocused ? widget.scale : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              foregroundDecoration: BoxDecoration(
                borderRadius: widget.borderRadius,
                border: Border.all(
                  color: _isFocused ? widget.focusBorderColor : Colors.transparent,
                  width: _isFocused ? 3.5 : 0.0,
                ),
                color: _isFocused
                    ? widget.focusBorderColor.withOpacity(0.08)
                    : Colors.transparent,
              ),
              child: ClipRRect(
                borderRadius: widget.borderRadius,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
