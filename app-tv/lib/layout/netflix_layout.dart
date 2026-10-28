import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_service.dart';
import '../models/update_model.dart';
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
import '../widgets/exit_confirm_dialog.dart';

class NetflixLayout extends StatefulWidget {
  final ApiService apiService;

  const NetflixLayout({super.key, required this.apiService});

  @override
  State<NetflixLayout> createState() => _NetflixLayoutState();
}

class _NetflixLayoutState extends State<NetflixLayout> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentTabIndex = 0; // 0: Home, 1: Xoilac, 2: Socolive, 3: Anime, 4: IPTV

  // Tab GlobalKeys to trigger reloads from Header bar
  final GlobalKey<NetflixHomeScreenState> _homeKey = GlobalKey<NetflixHomeScreenState>();
  final GlobalKey<FootballScreenState> _xoilacKey = GlobalKey<FootballScreenState>();
  final GlobalKey<FootballScreenState> _socoliveKey = GlobalKey<FootballScreenState>();
  final GlobalKey<NetflixAnimeScreenState> _animeKey = GlobalKey<NetflixAnimeScreenState>();
  final GlobalKey<IptvScreenState> _iptvKey = GlobalKey<IptvScreenState>();

  bool _isRefreshingHeader = false;

  // TV Remote navigation FocusNodes for sidebar (5 tabs + Refresh + Update + V1 switch + Profile = 9)
  final List<FocusNode> _sidebarFocusNodes = List.generate(9, (_) => FocusNode());
  final FocusScopeNode _contentFocusScopeNode = FocusScopeNode();
  final Map<int, FocusNode> _lastContentFocusPerTab = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkOtaUpdate(silent: true);
      SyncService.init(widget.apiService.baseUrl);
    });
  }

  @override
  void dispose() {
    for (final node in _sidebarFocusNodes) {
      node.dispose();
    }
    _contentFocusScopeNode.dispose();
    super.dispose();
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

  /// Chuyển focus từ sidebar sang vùng nội dung một cách ổn định:
  /// 1. Ưu tiên quay lại thẻ đã focus trước đó nếu nó vẫn còn hợp lệ và đang hiển thị trên màn hình.
  /// 2. Nếu không, chọn thẻ đang hiển thị gần nhất với vị trí mục sidebar (ngang hàng, sát mép trái).
  /// Tránh trường hợp focus nhảy tới thẻ đã cuộn khuất / thuộc tab cũ khiến trang cuộn lung tung.
  /// Chuyển focus từ sidebar sang vùng nội dung một cách xác định và mượt mà:
  /// 1. Nếu cùng tab và thẻ đã focus trước đó vẫn đang hiển thị: quay lại đúng thẻ đó.
  /// 2. Nếu chuyển tab hoặc thẻ cũ không còn hiển thị: focus trực tiếp vào điểm đón chính (primary node) của tab.
  /// 3. Fallback: Chọn thẻ trên cùng - bên trái nhất đang hiển thị trong viewport.
  void _moveFocusToContent() {
    final Size screen = MediaQuery.of(context).size;
    const double contentLeft = 68.0;

    Rect? getNodeRect(FocusNode node) {
      final ctx = node.context;
      if (ctx == null || !ctx.mounted) return null;
      final ro = ctx.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
      final offset = ro.localToGlobal(Offset.zero);
      return offset & ro.size;
    }

    bool isUsable(FocusNode node) {
      if (!node.canRequestFocus || node.skipTraversal || node is FocusScopeNode) return false;
      return getNodeRect(node) != null;
    }

    bool isOnScreen(Rect r) {
      if (r.width <= 0 || r.height <= 0) return false;
      final visible = r.intersect(Rect.fromLTWH(contentLeft, 0, screen.width - contentLeft, screen.height));
      if (visible.width <= 0 || visible.height <= 0) return false;
      return visible.width >= r.width * 0.5 && visible.height >= r.height * 0.5;
    }

    // 1. Thẻ đã focus trước đó trên cùng tab (nếu còn hiển thị trên màn hình)
    final FocusNode? lastFocused = _lastContentFocusPerTab[_currentTabIndex];
    if (lastFocused != null && isUsable(lastFocused)) {
      final r = getNodeRect(lastFocused);
      if (r != null && isOnScreen(r)) {
        lastFocused.requestFocus();
        return;
      }
    }

    // 2. Chuyển trực tiếp vào điểm đón chuẩn của Tab hiện tại
    switch (_currentTabIndex) {
      case 0: // Trang chủ: Thẻ nội dung đầu tiên trên Home
        final homeState = _homeKey.currentState;
        if (homeState != null && homeState.mounted) {
          final firstNode = homeState.firstCardFocusNode;
          if (firstNode.canRequestFocus && isUsable(firstNode)) {
            firstNode.requestFocus();
            return;
          }
        }
        break;

      case 1: // Xôi Lạc TV: Trận bóng đầu tiên
        final xoilacState = _xoilacKey.currentState;
        if (xoilacState != null && xoilacState.mounted) {
          final firstNode = xoilacState.firstMatchFocusNode;
          if (firstNode.canRequestFocus && isUsable(firstNode)) {
            firstNode.requestFocus();
            return;
          }
        }
        break;

      case 2: // Socolive TV: Trận bóng đầu tiên
        final socoliveState = _socoliveKey.currentState;
        if (socoliveState != null && socoliveState.mounted) {
          final firstNode = socoliveState.firstMatchFocusNode;
          if (firstNode.canRequestFocus && isUsable(firstNode)) {
            firstNode.requestFocus();
            return;
          }
        }
        break;

      case 3: // Anime & Phim: Thẻ "PHÁT NGAY" trên Billboard
        final animeState = _animeKey.currentState;
        if (animeState != null && animeState.mounted) {
          final playNode = animeState.billboardPlayFocusNode;
          if (playNode.canRequestFocus && isUsable(playNode)) {
            playNode.requestFocus();
            return;
          }
        }
        break;

      case 4: // Truyền hình IPTV: Kênh truyền hình đầu tiên
        final iptvState = _iptvKey.currentState;
        if (iptvState != null && iptvState.mounted) {
          final firstNode = iptvState.firstChannelCardFocusNode;
          if (firstNode.canRequestFocus && isUsable(firstNode)) {
            firstNode.requestFocus();
            return;
          }
        }
        break;
    }

    // 3. Fallback: Thẻ hiển thị trên cùng - bên trái nhất của vùng nội dung nhìn thấy
    FocusNode? best;
    double bestScore = double.infinity;
    for (final node in _contentFocusScopeNode.traversalDescendants) {
      if (!isUsable(node)) continue;
      if (node.descendants.any((d) => d.canRequestFocus && !d.skipTraversal)) continue;
      final r = getNodeRect(node);
      if (r == null || !isOnScreen(r)) continue;
      final double score = r.top * 2.0 + (r.left - contentLeft).clamp(0.0, double.infinity);
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }

    if (best != null) {
      best.requestFocus();
    } else {
      _contentFocusScopeNode.requestFocus();
    }
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

  Future<void> _refreshActiveTab() async {
    if (_isRefreshingHeader) return;
    setState(() {
      _isRefreshingHeader = true;
    });

    try {
      SyncService.syncFull(widget.apiService.baseUrl);
      switch (_currentTabIndex) {
        case 0:
          await _homeKey.currentState?.refresh();
          break;
        case 1:
          await _xoilacKey.currentState?.reloadMatches();
          break;
        case 2:
          await _socoliveKey.currentState?.reloadMatches();
          break;
        case 3:
          await _animeKey.currentState?.refresh();
          break;
        case 4:
          await _iptvKey.currentState?.refresh();
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật dữ liệu mới nhất!'),
            backgroundColor: Color(0xFF0284C7),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi cập nhật: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingHeader = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // iPad and iPhone both run on iOS and use the clean Hamburger Drawer mode
    final bool isDrawerMode = Platform.isIOS || MediaQuery.of(context).size.width < 750;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        // If in drawer mode: close drawer if open
        if (isDrawerMode && (_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
          Navigator.of(context).pop();
          return;
        }

        // On TV: If content has focus, move focus to sidebar first
        final sidebarHasFocus = _sidebarFocusNodes.any((n) => n.hasFocus);
        if (!sidebarHasFocus && !isDrawerMode) {
          _sidebarFocusNodes[_currentTabIndex].requestFocus();
          return;
        }

        // If on non-home tab: return to tab 0
        if (_currentTabIndex != 0) {
          setState(() {
            _currentTabIndex = 0;
          });
          if (!isDrawerMode) {
            _sidebarFocusNodes[0].requestFocus();
          }
          return;
        }

        // Tab 0 & in sidebar: confirm before quit app
        ExitConfirmDialog.show(context);
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFF0F0F0F),
        drawer: isDrawerMode ? _buildMobileDrawer() : null,
        body: SafeArea(
          child: isDrawerMode
              ? Column(
                  children: [
                    _buildMobileHeader(),
                    Expanded(
                      child: _buildIndexedTabContent(),
                    ),
                  ],
                )
              : Stack(
                  children: [
                    // 1. Main Content Area (Offset by 68px for the collapsed rail)
                    Positioned.fill(
                      left: 68,
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                            final primary = FocusManager.instance.primaryFocus;
                            // Để TextField (ô tìm kiếm) tự xử lý di chuyển con trỏ chữ
                            if (primary?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
                              return KeyEventResult.ignored;
                            }
                            // Check if primary focus has nowhere left to go inside content
                            final moved = primary?.focusInDirection(TraversalDirection.left) ?? false;
                            if (!moved) {
                              // Reached left edge of content: jump directly to active sidebar item!
                              if (primary != null) {
                                _lastContentFocusPerTab[_currentTabIndex] = primary;
                              }
                              _sidebarFocusNodes[_currentTabIndex].requestFocus();
                            }
                            // Luôn chặn sự kiện tại đây: nếu trả về ignored sau khi đã di chuyển,
                            // Shortcuts mặc định sẽ di chuyển thêm 1 lần nữa -> con trỏ nhảy 2 ô.
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: FocusScope(
                          node: _contentFocusScopeNode,
                          child: _buildIndexedTabContent(),
                        ),
                      ),
                    ),

                    // 2. Left Rail Sidebar (Stack overlay on top - highest z-index)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: NetflixSidebar(
                        selectedIndex: _currentTabIndex,
                        focusNodes: _sidebarFocusNodes,
                        isRefreshing: _isRefreshingHeader,
                        onRefresh: _refreshActiveTab,
                        onCheckUpdate: () => _checkOtaUpdate(silent: false),
                        onMoveToContent: _moveFocusToContent,
                        onTabSelected: (idx) {
                          setState(() {
                            _currentTabIndex = idx;
                          });
                        },
                        onSwitchToOldUI: _switchToOldUI,
                        onProfilePressed: _handleProfileButton,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // =========================================================================
  // SHARED INDEXED TAB CONTENT
  // =========================================================================
  Widget _buildIndexedTabContent() {
    return IndexedStack(
      index: _currentTabIndex,
      children: [
        // Tab 0: Netflix Home (Billboard + Horizontal Carousels)
        ExcludeFocus(
          excluding: _currentTabIndex != 0,
          child: NetflixHomeScreen(
            key: _homeKey,
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
            key: _xoilacKey,
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
            key: _socoliveKey,
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
            key: _animeKey,
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
            key: _iptvKey,
            apiService: widget.apiService,
            isActive: _currentTabIndex == 4,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // MOBILE TOP BAR (HAMBURGER BUTTON + LOGO + TITLE + PROFILE)
  // =========================================================================
  Widget _buildMobileHeader() {
    final titles = [
      'Trang chủ',
      'Xôi Lạc TV',
      'Socolive TV',
      'Anime & Phim',
      'Truyền Hình (IPTV)',
    ];
    final currentTitle = _currentTabIndex < titles.length ? titles[_currentTabIndex] : 'VolPi Media';

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF262626), width: 1.0)),
      ),
      child: Row(
        children: [
          // ☰ Hamburger Button
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 8),

          // Logo
          SizedBox(
            width: 24,
            height: 24,
            child: Image.asset('assets/volpi_logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(width: 8),

          // Title
          Expanded(
            child: Text(
              currentTitle,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 🔄 Làm Mới Button
          IconButton(
            icon: _isRefreshingHeader
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 21),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Làm mới',
            onPressed: _refreshActiveTab,
          ),

          const SizedBox(width: 4),

          // Check OTA
          IconButton(
            icon: const Icon(Icons.system_update_rounded, color: Color(0xFF38BDF8), size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Kiểm tra cập nhật',
            onPressed: () => _checkOtaUpdate(silent: false),
          ),

          const SizedBox(width: 6),

          // Profile / Secret Passcode
          GestureDetector(
            onTap: _handleProfileButton,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Center(
                child: Text(
                  'VP',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // MOBILE SLIDE-OUT DRAWER
  // =========================================================================
  Widget _buildMobileDrawer() {
    final menuItems = [
      {'icon': Icons.home_rounded, 'label': 'Trang chủ'},
      {'icon': Icons.sports_soccer_rounded, 'label': 'Xôi Lạc TV'},
      {'icon': Icons.sports_rounded, 'label': 'Socolive TV'},
      {'icon': Icons.auto_awesome_rounded, 'label': 'Anime & Phim'},
      {'icon': Icons.live_tv_rounded, 'label': 'Truyền Hình (IPTV)'},
    ];

    return Drawer(
      backgroundColor: const Color(0xFF141414),
      width: 280,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Image.asset('assets/volpi_logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VOLPI MEDIA',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                        ),
                        Text(
                          'NETFLIX CINEMA',
                          style: TextStyle(color: Color(0xFFE50914), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF262626), height: 1),

            const SizedBox(height: 10),

            // Navigation Items
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: menuItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, idx) {
                  final item = menuItems[idx];
                  final isSelected = _currentTabIndex == idx;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _currentTabIndex = idx;
                      });
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF262626) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? const Border(left: BorderSide(color: Color(0xFFE50914), width: 3.5))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 22,
                            color: isSelected ? const Color(0xFFE50914) : Colors.white70,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              item['label'] as String,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 14,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const Divider(color: Color(0xFF262626), height: 1),

            // Bottom Actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // 1. Làm mới dữ liệu
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _refreshActiveTab();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          _isRefreshingHeader
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF38BDF8)),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Làm mới dữ liệu',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 2. Cập nhật ứng dụng
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _checkOtaUpdate(silent: false);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.system_update_rounded, size: 18, color: Color(0xFF38BDF8)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Cập nhật ứng dụng',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 3. Switch to V1
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _switchToOldUI();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.restore_page_rounded, size: 18, color: Color(0xFF38BDF8)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Giao diện Cũ (V1)',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Profile
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      _handleProfileButton();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
                              child: Text('VP', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Tài khoản & Phim riêng tư',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
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
    );
  }
}
