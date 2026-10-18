import 'package:flutter/material.dart';
import '../api/api_service.dart';
import '../models/update_model.dart';
import '../screens/anime_screen.dart';
import '../screens/football_screen.dart';
import '../screens/iptv_screen.dart';
import '../screens/netflix/netflix_anime_screen.dart';
import '../screens/netflix/netflix_home_screen.dart';
import '../screens/secret_movie_screen.dart';
import '../services/player_settings_service.dart';
import '../services/sync_service.dart';
import '../services/update_service.dart';
import '../widgets/netflix/netflix_sidebar.dart';
import '../widgets/passcode_dialog.dart';
import '../widgets/update_dialog.dart';

class NetflixLayout extends StatefulWidget {
  final ApiService apiService;

  const NetflixLayout({super.key, required this.apiService});

  @override
  State<NetflixLayout> createState() => _NetflixLayoutState();
}

class _NetflixLayoutState extends State<NetflixLayout> {
  int _currentTabIndex = 0; // 0: Home, 1: Xoilac, 2: Socolive, 3: Anime, 4: IPTV

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOtaUpdate(silent: true);
      SyncService.pullFromServer(widget.apiService.baseUrl);
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
          onExit: () {},
        ),
      ),
    );
  }

  void _handleProfileButton() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PasscodeDialog(onSuccess: _onProfileUnlocked),
    );
  }

  void _switchToOldUI() {
    PlayerSettingsService.instance.setUseNetflixUI(false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã chuyển về Giao diện Cũ (V1).'),
        backgroundColor: Color(0xFF0284C7),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _currentTabIndex != 0) {
          // TV Remote Back button: Return to Netflix Home tab first instead of quitting
          setState(() {
            _currentTabIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: SafeArea(
          child: Row(
            children: [
              // 1. Netflix Left Rail Sidebar (Interactive D-Pad & Hover)
              NetflixSidebar(
                selectedIndex: _currentTabIndex,
                onTabSelected: (idx) {
                  setState(() {
                    _currentTabIndex = idx;
                  });
                },
                onSwitchToOldUI: _switchToOldUI,
                onProfilePressed: _handleProfileButton,
              ),

              // 2. Main Content Area with IndexedStack & ExcludeFocus (Trap Door #1 & #3 Avoided)
              Expanded(
                child: IndexedStack(
                  index: _currentTabIndex,
                  children: [
                    // Tab 0: Netflix Home (Billboard + Horizontal Carousels)
                    ExcludeFocus(
                      excluding: _currentTabIndex != 0,
                      child: NetflixHomeScreen(
                        apiService: widget.apiService,
                        onNavigateTab: (tabIdx) {
                          setState(() {
                            _currentTabIndex = tabIdx;
                          });
                        },
                      ),
                    ),

                    // Tab 1: Xôi Lạc TV
                    ExcludeFocus(
                      excluding: _currentTabIndex != 1,
                      child: FootballScreen(
                        apiService: widget.apiService,
                        source: 'xoilac',
                        title: 'Xôi Lạc TV',
                        isActive: _currentTabIndex == 1,
                      ),
                    ),

                    // Tab 2: Socolive TV
                    ExcludeFocus(
                      excluding: _currentTabIndex != 2,
                      child: FootballScreen(
                        apiService: widget.apiService,
                        source: 'socolive',
                        title: 'Socolive TV',
                        isActive: _currentTabIndex == 2,
                      ),
                    ),

                    // Tab 3: Anime & Phim
                    ExcludeFocus(
                      excluding: _currentTabIndex != 3,
                      child: NetflixAnimeScreen(
                        apiService: widget.apiService,
                        onNavigateTab: (tabIdx) {
                          setState(() {
                            _currentTabIndex = tabIdx;
                          });
                        },
                      ),
                    ),

                    // Tab 4: Truyền Hình (IPTV)
                    ExcludeFocus(
                      excluding: _currentTabIndex != 4,
                      child: IptvScreen(
                        apiService: widget.apiService,
                        isActive: _currentTabIndex == 4,
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
