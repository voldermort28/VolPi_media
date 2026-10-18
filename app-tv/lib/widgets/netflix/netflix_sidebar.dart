import 'package:flutter/material.dart';
import '../tv_focusable_card.dart';

class NetflixSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSwitchToOldUI;
  final VoidCallback onProfilePressed;
  final FocusNode? firstFocusNode;

  const NetflixSidebar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onSwitchToOldUI,
    required this.onProfilePressed,
    this.firstFocusNode,
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

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      onFocusChange: (hasFocus) {
        setState(() {
          _isExpanded = hasFocus;
        });
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
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0284C7).withOpacity(0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
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

              // 2. Navigation Items
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: _menuItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, idx) {
                    final item = _menuItems[idx];
                    final isSelected = widget.selectedIndex == idx;

                    return TvFocusableCard(
                      focusNode: (idx == 0 && widget.firstFocusNode != null)
                          ? widget.firstFocusNode
                          : null,
                      onTap: () => widget.onTabSelected(idx),
                      borderRadius: BorderRadius.circular(8),
                      focusBorderColor: Colors.white,
                      scale: 1.02,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF262626)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
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
                              item['icon'] as IconData,
                              size: 22,
                              color: isSelected
                                  ? const Color(0xFFE50914)
                                  : Colors.white70,
                            ),
                            if (_isExpanded) ...[
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item['label'] as String,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontSize: 13,
                                    fontWeight: isSelected
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
                    );
                  },
                ),
              ),

              const Divider(color: Color(0xFF262626), height: 1, thickness: 1),

              // 3. Bottom Actions: Switch back to V1 & Profile
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    // Switch back to V1
                    TvFocusableCard(
                      onTap: widget.onSwitchToOldUI,
                      borderRadius: BorderRadius.circular(8),
                      focusBorderColor: const Color(0xFF38BDF8),
                      scale: 1.02,
                      child: Container(
                        height: 40,
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

                    const SizedBox(height: 8),

                    // Profile / Secret
                    TvFocusableCard(
                      onTap: widget.onProfilePressed,
                      borderRadius: BorderRadius.circular(8),
                      focusBorderColor: Colors.white,
                      scale: 1.02,
                      child: Container(
                        height: 40,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
