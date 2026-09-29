import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../models/update_model.dart';
import '../screens/football_screen.dart';
import '../screens/anime_screen.dart';
import '../screens/iptv_screen.dart';
import '../screens/secret_movie_screen.dart';
import '../services/update_service.dart';
import '../widgets/profile_button.dart';
import '../widgets/tv_focusable_card.dart';
import '../widgets/update_dialog.dart';

class AdaptiveLayout extends StatefulWidget {
  final ApiService apiService;

  const AdaptiveLayout({super.key, required this.apiService});

  @override
  State<AdaptiveLayout> createState() => _AdaptiveLayoutState();
}

class _AdaptiveLayoutState extends State<AdaptiveLayout> {
  int _currentTabIndex = 0; // 0: Football, 1: Anime

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOtaUpdate(silent: true);
    });
  }

  Future<void> _checkOtaUpdate({bool silent = false}) async {
    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (updateInfo != null && updateInfo.hasUpdate) {
        UpdateDialog.show(context, updateInfo);
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ứng dụng đang ở phiên bản mới nhất!'),
            backgroundColor: Color(0xFF0284C7),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể kiểm tra cập nhật: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _onProfileUnlocked() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SecretMovieScreen(
          apiService: widget.apiService,
          onExit: () {
            // ZERO-TRACE: Reset any lingering state
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isLargeScreen = constraints.maxWidth >= 900;
        final bool isMediumScreen = constraints.maxWidth >= 600 && constraints.maxWidth < 900;

        // If iPad / Tablet in landscape: use Left Sidebar (NavigationRail)
        if (isLargeScreen || isMediumScreen) {
          return _buildTabletLayout();
        }

        // Else Phone / Portrait: use BottomNavigationBar + Top Header
        return _buildPhoneLayout();
      },
    );
  }

  // =========================================================================
  // TABLET & TV LAYOUT (TV Top Bar or iPad Left Sidebar)
  // =========================================================================
  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar for TV & Large Screens
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
              ),
              child: Row(
                children: [
                  // App Logo & Name
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'VolPi Media',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),

                  const SizedBox(width: 40),

                  // TV Nav Tabs
                  _buildTvNavTab(index: 0, label: 'Bóng Đá Trực Tiếp', icon: Icons.sports_soccer_rounded),
                  const SizedBox(width: 12),
                  _buildTvNavTab(index: 1, label: 'Anime & Phim', icon: Icons.auto_awesome_rounded),
                  const SizedBox(width: 12),
                  _buildTvNavTab(index: 2, label: 'Truyền Hình (IPTV)', icon: Icons.live_tv_rounded),

                  const Spacer(),

                  // OTA Update Check Button
                  SizedBox(
                    height: 38,
                    child: TvFocusableCard(
                      onTap: () => _checkOtaUpdate(silent: false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: const Color(0xFF1E293B),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.system_update_rounded, color: Color(0xFF38BDF8), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Cập nhật',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Profile Button with Passcode 3105
                  ProfileButton(onUnlocked: _onProfileUnlocked),
                ],
              ),
            ),

            // Tab Content
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: [
                  FootballScreen(apiService: widget.apiService),
                  AnimeScreen(apiService: widget.apiService),
                  IptvScreen(apiService: widget.apiService),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTvNavTab({required int index, required String label, required IconData icon}) {
    final bool isSelected = _currentTabIndex == index;

    return SizedBox(
      height: 42,
      child: TvFocusableCard(
        onTap: () {
          setState(() {
            _currentTabIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // PHONE LAYOUT (iPhone / Mobile 1-hand touch)
  // =========================================================================
  Widget _buildPhoneLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0284C7), Color(0xFF38BDF8)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Text(
              'VolPi Media',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_rounded, color: Color(0xFF38BDF8), size: 20),
            tooltip: 'Kiểm tra cập nhật',
            onPressed: () => _checkOtaUpdate(silent: false),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: ProfileButton(onUnlocked: _onProfileUnlocked),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          FootballScreen(apiService: widget.apiService),
          AnimeScreen(apiService: widget.apiService),
          IptvScreen(apiService: widget.apiService),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E293B), width: 1.5)),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF0F172A),
          currentIndex: _currentTabIndex,
          selectedItemColor: const Color(0xFF38BDF8),
          unselectedItemColor: const Color(0xFF64748B),
          selectedFontSize: 12,
          unselectedFontSize: 12,
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.sports_soccer_rounded),
              label: 'Bóng Đá',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_rounded),
              label: 'Anime',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.live_tv_rounded),
              label: 'Truyền Hình',
            ),
          ],
        ),
      ),
    );
  }
}
