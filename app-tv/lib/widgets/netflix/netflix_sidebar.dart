import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tv_focusable_card.dart';

class NetflixSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSwitchToOldUI;
  final VoidCallback onProfilePressed;
  final VoidCallback? onRefresh;
  final VoidCallback? onCheckUpdate;
  final bool isRefreshing;
  final List<FocusNode>? focusNodes;
  final VoidCallback? onMoveToContent;

  const NetflixSidebar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onSwitchToOldUI,
    required this.onProfilePressed,
    this.onRefresh,
    this.onCheckUpdate,
    this.isRefreshing = false,
    this.focusNodes,
    this.onMoveToContent,
  });

  @override
  State<NetflixSidebar> createState() => _NetflixSidebarState();
}

class _NetflixSidebarState extends State<NetflixSidebar> {
  bool _isExpanded = false;

  final List<Map<String, dynamic>> _menuItems = [
    {
      'icon': Icons.home_rounded,
      'label': 'Trang chủ',
    },
    {
      'icon': Icons.sports_soccer_rounded,
      'label': 'Xôi Lạc TV',
    },
    {
      'icon': Icons.sports_rounded,
      'label': 'Socolive TV',
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'label': 'Anime & Phim',
    },
    {
      'icon': Icons.live_tv_rounded,
      'label': 'Truyền Hình (IPTV)',
    },
  ];

  KeyEventResult _handleSidebarItemKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < 4) {
        widget.focusNodes?[index + 1].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 4) {
        // Move from IPTV (4) to Làm mới (5)
        widget.focusNodes?[5].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 5) {
        // Move from Làm mới (5) to Cập nhật (6)
        widget.focusNodes?[6].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 6) {
        // Move from Cập nhật (6) to V1 Switch (7)
        widget.focusNodes?[7].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 7) {
        // Move from V1 Switch (7) to Profile (8)
        widget.focusNodes?[8].requestFocus();
        return KeyEventResult.handled;
      } else if (index >= 8) {
        // Reached bottom of sidebar
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0 && index <= 4) {
        widget.focusNodes?[index - 1].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 0) {
        // Reached top of sidebar
        return KeyEventResult.handled;
      } else if (index == 5) {
        // Move from Làm mới (5) up to IPTV (4)
        widget.focusNodes?[4].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 6) {
        // Move from Cập nhật (6) up to Làm mới (5)
        widget.focusNodes?[5].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 7) {
        // Move from V1 Switch (7) up to Cập nhật (6)
        widget.focusNodes?[6].requestFocus();
        return KeyEventResult.handled;
      } else if (index == 8) {
        // Move from Profile (8) up to V1 Switch (7)
        widget.focusNodes?[7].requestFocus();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onMoveToContent?.call();
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      // Keep focus inside sidebar
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          setState(() {
            _isExpanded = hasFocus;
          });
        },
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (widget.onMoveToContent != null) {
              widget.onMoveToContent!();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _isExpanded = true),
          onExit: (_) => setState(() => _isExpanded = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: _isExpanded ? 220 : 68,
            decoration: BoxDecoration(
              color: const Color(0xFF000000).withOpacity(0.96),
              border: const Border(
                right: BorderSide(color: Color(0xFF262626), width: 1.0),
              ),
              boxShadow: _isExpanded
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.8),
                        blurRadius: 24,
                        offset: const Offset(4, 0),
                      )
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Logo Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: Image.asset(
                          'assets/volpi_logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (_isExpanded) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VOLPI MEDIA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'NETFLIX CINEMA',
                                style: TextStyle(
                                  color: Color(0xFFE50914),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(color: Color(0xFF262626), height: 1, thickness: 1),

                const SizedBox(height: 10),

                // 2. Navigation Items (Fixed Column with Spacer to avoid scrollable traversal leaking)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    children: [
                      for (int idx = 0; idx < _menuItems.length; idx++) ...[
                        if (idx > 0) const SizedBox(height: 6),
                        Focus(
                          onKeyEvent: (node, event) => _handleSidebarItemKey(idx, event),
                          child: TvFocusableCard(
                            focusNode: (widget.focusNodes != null && idx < widget.focusNodes!.length)
                                ? widget.focusNodes![idx]
                                : null,
                            onTap: () => widget.onTabSelected(idx),
                            borderRadius: BorderRadius.circular(8),
                            focusBorderColor: Colors.white,
                            scale: 1.02,
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: widget.selectedIndex == idx
                                    ? const Color(0xFF262626)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: widget.selectedIndex == idx
                                    ? const Border(
                                        left: BorderSide(
                                          color: Color(0xFFE50914),
                                          width: 3.5,
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _menuItems[idx]['icon'] as IconData,
                                    size: 22,
                                    color: widget.selectedIndex == idx
                                        ? const Color(0xFFE50914)
                                        : Colors.white70,
                                  ),
                                  if (_isExpanded) ...[
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        _menuItems[idx]['label'] as String,
                                        style: TextStyle(
                                          color: widget.selectedIndex == idx
                                              ? Colors.white
                                              : Colors.white70,
                                          fontSize: 13,
                                          fontWeight: widget.selectedIndex == idx
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Spacer(),

                const Divider(color: Color(0xFF262626), height: 1, thickness: 1),

                // 3. Bottom Actions: Refresh, Update, Switch to V1, Profile
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      // 1. Làm mới dữ liệu
                      Focus(
                        onKeyEvent: (node, event) => _handleSidebarItemKey(5, event),
                        child: TvFocusableCard(
                          focusNode: (widget.focusNodes != null && widget.focusNodes!.length > 5)
                              ? widget.focusNodes![5]
                              : null,
                          onTap: widget.onRefresh,
                          borderRadius: BorderRadius.circular(8),
                          focusBorderColor: const Color(0xFF38BDF8),
                          scale: 1.02,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withOpacity(0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                widget.isRefreshing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF38BDF8),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.refresh_rounded,
                                        size: 18,
                                        color: Color(0xFF38BDF8),
                                      ),
                                if (_isExpanded) ...[
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Làm mới dữ liệu',
                                      style: TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // 2. Cập nhật ứng dụng
                      Focus(
                        onKeyEvent: (node, event) => _handleSidebarItemKey(6, event),
                        child: TvFocusableCard(
                          focusNode: (widget.focusNodes != null && widget.focusNodes!.length > 6)
                              ? widget.focusNodes![6]
                              : null,
                          onTap: widget.onCheckUpdate,
                          borderRadius: BorderRadius.circular(8),
                          focusBorderColor: const Color(0xFF38BDF8),
                          scale: 1.02,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withOpacity(0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.system_update_rounded,
                                  size: 18,
                                  color: Color(0xFF38BDF8),
                                ),
                                if (_isExpanded) ...[
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Cập nhật ứng dụng',
                                      style: TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // 3. Switch back to V1
                      Focus(
                        onKeyEvent: (node, event) => _handleSidebarItemKey(7, event),
                        child: TvFocusableCard(
                          focusNode: (widget.focusNodes != null && widget.focusNodes!.length > 7)
                              ? widget.focusNodes![7]
                              : null,
                          onTap: widget.onSwitchToOldUI,
                          borderRadius: BorderRadius.circular(8),
                          focusBorderColor: const Color(0xFF38BDF8),
                          scale: 1.02,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withOpacity(0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.restore_page_rounded,
                                  size: 18,
                                  color: Color(0xFF38BDF8),
                                ),
                                if (_isExpanded) ...[
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Giao diện Cũ (V1)',
                                      style: TextStyle(
                                        color: Color(0xFF38BDF8),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // 4. Profile / Secret
                      Focus(
                        onKeyEvent: (node, event) => _handleSidebarItemKey(8, event),
                        child: TvFocusableCard(
                          focusNode: (widget.focusNodes != null && widget.focusNodes!.length > 8)
                              ? widget.focusNodes![8]
                              : null,
                          onTap: widget.onProfilePressed,
                          borderRadius: BorderRadius.circular(8),
                          focusBorderColor: Colors.white,
                          scale: 1.02,
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF171717),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'VP',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_isExpanded) ...[
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Tài khoản & Phim',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
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
    );
  }
}
