import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvFocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;
  final Color focusBorderColor;
  final BorderRadius borderRadius;
  final FocusNode? focusNode;
  final bool autoFocus;

  const TvFocusableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 1.06,
    this.focusBorderColor = const Color(0xFF38BDF8), // Electric Sky Blue
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.focusNode,
    this.autoFocus = false,
  });

  @override
  State<TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<TvFocusableCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autoFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          _focusNode.requestFocus();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _isFocused ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _isFocused ? widget.focusBorderColor : Colors.transparent,
                width: _isFocused ? 3.0 : 0.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: widget.focusBorderColor.withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
