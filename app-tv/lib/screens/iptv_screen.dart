import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/iptv_channel_model.dart';
import '../models/match_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class IptvScreen extends StatefulWidget {
  final ApiService apiService;

  const IptvScreen({super.key, required this.apiService});

  @override
  State<IptvScreen> createState() => _IptvScreenState();
}

class IptvCategoryItem {
  final String id;
  final String title;
  final IconData icon;

  const IptvCategoryItem({
    required this.id,
    required this.title,
    required this.icon,
  });
}

const List<IptvCategoryItem> kIptvCategories = [
  IptvCategoryItem(id: 'FOOTBALL', title: 'Bóng đá', icon: Icons.sports_soccer_rounded),
  IptvCategoryItem(id: 'OTHER_SPORTS', title: 'Thể thao khác', icon: Icons.sports_volleyball_rounded),
  IptvCategoryItem(id: 'FIXED_TV', title: 'Truyền hình', icon: Icons.tv_rounded),
  IptvCategoryItem(id: 'PINNED', title: 'Đã ghim', icon: Icons.star_rounded),
  IptvCategoryItem(id: 'ALL', title: 'Tất cả', icon: Icons.public_rounded),
];

class _IptvScreenState extends State<IptvScreen> {
  List<IptvChannelModel> _allChannels = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _selectedCategory = 'FOOTBALL'; // Mặc định bóng đá lên đầu
  String _selectedSourceId = 'ALL';
  String _selectedGroup = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadChannels(forceRefresh: false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChannels({bool forceRefresh = false, bool triggerServerFetch = false}) async {
    setState(() {
      if (forceRefresh) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
      _errorMessage = null;
    });

    try {
      if (triggerServerFetch) {
        await widget.apiService.refreshIptvSourceOnServer();
      }

      final channels = await widget.apiService.getIptvChannels(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _allChannels = channels;
          _isLoading = false;
          _isRefreshing = false;
          final hasFootball = _allChannels.any((c) => c.category == 'FOOTBALL');
          if (!hasFootball && _selectedCategory == 'FOOTBALL') {
            _selectedCategory = 'ALL';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _errorMessage = 'Không thể tải danh sách kênh IPTV: ${e.toString()}';
        });
      }
    }
  }

  List<IptvSourceModel> _getAvailableSources() {
    final Map<String, String> sourceNames = {};
    final Map<String, int> sourceCounts = {};

    for (final c in _allChannels) {
      final sId = c.sourceId.isNotEmpty ? c.sourceId : 'pl-default';
      final sName = c.sourceName.isNotEmpty ? c.sourceName : 'Kênh Quốc Gia';
      sourceNames[sId] = sName;
      sourceCounts[sId] = (sourceCounts[sId] ?? 0) + 1;
    }

    final List<IptvSourceModel> sources = [
      IptvSourceModel(id: 'ALL', name: 'Tất Cả Các Nguồn', count: _allChannels.length),
    ];

    sourceNames.forEach((id, name) {
      sources.add(IptvSourceModel(id: id, name: name, count: sourceCounts[id] ?? 0));
    });

    return sources;
  }

  int _getCategoryCount(String categoryId) {
    return _allChannels.where((c) {
      if (_selectedSourceId != 'ALL' && c.sourceId != _selectedSourceId) return false;
      if (categoryId == 'PINNED') return c.isPinned;
      if (categoryId == 'ALL') return true;
      return c.category == categoryId;
    }).length;
  }

  String _getCategoryTitle(String categoryId) {
    for (final item in kIptvCategories) {
      if (item.id == categoryId) return item.title;
    }
    return 'Bóng đá';
  }

  List<String> _getAvailableGroups() {
    final Set<String> groups = {};
    for (final c in _allChannels) {
      if (_selectedSourceId != 'ALL' && c.sourceId != _selectedSourceId) continue;

      if (_selectedCategory == 'PINNED') {
        if (!c.isPinned) continue;
      } else if (_selectedCategory != 'ALL') {
        if (c.category != _selectedCategory) continue;
      }

      if (c.group.isNotEmpty) {
        groups.add(c.group);
      }
    }
    final sorted = groups.toList()..sort();
    return ['ALL', if (_selectedCategory != 'PINNED') '⭐ Yêu Thích', ...sorted];
  }

  List<IptvChannelModel> _getFilteredChannels() {
    final list = _allChannels.where((c) {
      // 1. Source / Playlist filter
      if (_selectedSourceId != 'ALL' && c.sourceId != _selectedSourceId) {
        return false;
      }

      // 2. Category filter
      if (_selectedCategory == 'PINNED') {
        if (!c.isPinned) return false;
      } else if (_selectedCategory != 'ALL') {
        if (c.category != _selectedCategory) return false;
      }

      // 3. Group filter
      if (_selectedGroup == '⭐ Yêu Thích') {
        if (!c.isPinned) return false;
      } else if (_selectedGroup != 'ALL') {
        if (c.group != _selectedGroup) return false;
      }

      // 4. Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = c.name.toLowerCase().contains(q) || c.cleanTitle.toLowerCase().contains(q);
        final groupMatch = c.group.toLowerCase().contains(q);
        final sourceMatch = c.sourceName.toLowerCase().contains(q);
        if (!nameMatch && !groupMatch && !sourceMatch) return false;
      }

      return true;
    }).toList();

    // 5. Smart chronological & status sorting
    list.sort((a, b) {
      // 1. Pinned channels first
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;

      // 2. In ALL tab, FOOTBALL (1) ALWAYS first, then OTHER_SPORTS (2), then FIXED_TV (3)
      if (_selectedCategory == 'ALL') {
        const catWeight = {'FOOTBALL': 1, 'OTHER_SPORTS': 2, 'FIXED_TV': 3};
        final wA = catWeight[a.category] ?? 3;
        final wB = catWeight[b.category] ?? 3;
        if (wA != wB) return wA.compareTo(wB);
      }

      // 3. For FOOTBALL: Area 1 (Famous/VN, priorityLevel 1 & 2) before Area 2 (Others, priorityLevel 3)
      if (a.category == 'FOOTBALL' && b.category == 'FOOTBALL') {
        if (a.priorityLevel != b.priorityLevel) {
          return a.priorityLevel.compareTo(b.priorityLevel);
        }
      }

      // 4. Within the category, Live matches first
      if (a.isLive && !b.isLive) return -1;
      if (!a.isLive && b.isLive) return 1;

      // Chronological match timestamp
      if (a.matchTimestamp > 0 && b.matchTimestamp > 0) {
        if (a.matchTimestamp != b.matchTimestamp) return a.matchTimestamp.compareTo(b.matchTimestamp);
      } else if (a.matchTimestamp > 0 && b.matchTimestamp == 0) {
        return -1;
      } else if (a.matchTimestamp == 0 && b.matchTimestamp > 0) {
        return 1;
      }

      return a.name.compareTo(b.name);
    });

    return list;
  }

  void _showSourceSelectionDialog(List<IptvSourceModel> sources) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF334155), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.playlist_play_rounded, color: Color(0xFF38BDF8), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Chọn Nguồn Playlist IPTV',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: sources.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, index) {
                final source = sources[index];
                final isSelected = _selectedSourceId == source.id;

                return TvFocusableCard(
                  onTap: () {
                    setState(() {
                      _selectedSourceId = source.id;
                      _selectedGroup = 'ALL';
                    });
                    Navigator.of(dialogCtx).pop();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: isSelected ? const Color(0xFF38BDF8) : Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            source.name,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Text(
                            '${source.count} kênh',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Đóng', style: TextStyle(color: Colors.white60)),
            ),
          ],
        );
      },
    );
  }

  void _playChannel(IptvChannelModel channel, List<IptvChannelModel> currentList) {
    if (channel.url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kênh này hiện không có đường dẫn phát.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final availableChannels = currentList.map((c) => c.toStreamChannel(baseUrl: widget.apiService.baseUrl)).toList();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: channel.getPlaybackUrl(baseUrl: widget.apiService.baseUrl),
          title: channel.name,
          subtitle: channel.group,
          headers: channel.headers,
          availableChannels: availableChannels,
          isLive: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF38BDF8)),
            SizedBox(height: 16),
            Text(
              'Đang tải danh sách kênh truyền hình...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 54),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TvFocusableCard(
                onTap: () => _loadChannels(forceRefresh: true),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: const Color(0xFF0284C7),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Thử lại',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final sources = _getAvailableSources();
    final currentSource = sources.firstWhere(
      (s) => s.id == _selectedSourceId,
      orElse: () => sources.first,
    );
    final filteredChannels = _getFilteredChannels();
    final groups = _getAvailableGroups();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool showSidebar = constraints.maxWidth >= 700;
        final bool isLargeScreen = constraints.maxWidth >= 1100;
        final bool isMediumScreen = constraints.maxWidth >= 850 && constraints.maxWidth < 1100;

        int crossAxisCount = 2;
        if (isLargeScreen) {
          crossAxisCount = 4;
        } else if (isMediumScreen) {
          crossAxisCount = 3;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: showSidebar
              ? Row(
                  children: [
                    // LEFT SIDEBAR (Category, Source, Groups)
                    _buildLeftSidebar(sources, groups),

                    // RIGHT MAIN CONTENT (Header & Full Height Channel Grid)
                    Expanded(
                      child: _buildMainContent(filteredChannels, crossAxisCount, isLargeScreen),
                    ),
                  ],
                )
              : _buildMobileContent(sources, groups, filteredChannels, crossAxisCount),
        );
      },
    );
  }

  Widget _buildLeftSidebar(List<IptvSourceModel> sources, List<String> groups) {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF0B1322),
        border: Border(right: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.live_tv_rounded, color: Color(0xFF38BDF8), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRUYỀN HÌNH',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'IPTV & Thể Thao',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Color(0xFF1E293B), height: 1, thickness: 1),

          // Sidebar Navigation List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    'MÔN THỂ THAO & PHÂN LOẠI',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                // Categories
                ...kIptvCategories.map((cat) {
                  final isSelected = _selectedCategory == cat.id;
                  final count = _getCategoryCount(cat.id);

                  Color activeColor = const Color(0xFF0284C7);
                  Color activeBorder = const Color(0xFF38BDF8);
                  Color countBadgeBg = const Color(0xFF075985);

                  if (cat.id == 'FOOTBALL') {
                    activeColor = const Color(0xFF059669);
                    activeBorder = const Color(0xFF34D399);
                    countBadgeBg = const Color(0xFF064E3B);
                  } else if (cat.id == 'OTHER_SPORTS') {
                    activeColor = const Color(0xFF7C3AED);
                    activeBorder = const Color(0xFFA78BFA);
                    countBadgeBg = const Color(0xFF4C1D95);
                  } else if (cat.id == 'PINNED') {
                    activeColor = const Color(0xFFD97706);
                    activeBorder = const Color(0xFFF59E0B);
                    countBadgeBg = const Color(0xFF78350F);
                  } else if (cat.id == 'ALL') {
                    activeColor = const Color(0xFF334155);
                    activeBorder = const Color(0xFF64748B);
                    countBadgeBg = const Color(0xFF1E293B);
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TvFocusableCard(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat.id;
                          _selectedGroup = 'ALL';
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: isSelected ? activeColor : const Color(0xFF161E2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? activeBorder : const Color(0xFF1E293B),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              cat.icon,
                              size: 18,
                              color: isSelected ? Colors.white : Colors.white60,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                cat.title,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected ? countBadgeBg : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? activeBorder.withOpacity(0.5) : const Color(0xFF334155),
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.white54,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    'NGUỒN PLAYLIST',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                TvFocusableCard(
                  onTap: () => _showSourceSelectionDialog(sources),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: _selectedSourceId != 'ALL'
                          ? const Color(0xFF0284C7).withOpacity(0.2)
                          : const Color(0xFF161E2E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectedSourceId != 'ALL' ? const Color(0xFF38BDF8) : const Color(0xFF1E293B),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_play_rounded, size: 18, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sources.firstWhere((s) => s.id == _selectedSourceId, orElse: () => sources.first).name,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down_rounded, color: Colors.white60, size: 20),
                      ],
                    ),
                  ),
                ),

                if (groups.length > 2) ...[
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.only(left: 6, bottom: 8),
                    child: Text(
                      'NHÓM ĐÀI / GIẢI ĐẤU',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  ...groups.map((group) {
                    final isSelected = _selectedGroup == group;
                    final isFav = group == '⭐ Yêu Thích';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TvFocusableCard(
                        onTap: () {
                          setState(() {
                            _selectedGroup = group;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isFav ? const Color(0xFFD97706) : const Color(0xFF0284C7))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? (isFav ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8))
                                  : Colors.transparent,
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            group == 'ALL' ? 'Tất cả nhóm' : group,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white60,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(List<IptvChannelModel> filteredChannels, int crossAxisCount, bool isLargeScreen) {
    return Column(
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
          ),
          child: Row(
            children: [
              Text(
                _getCategoryTitle(_selectedCategory),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5)),
                ),
                child: Text(
                  '${filteredChannels.length} / ${_allChannels.length} kênh',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const Spacer(),

              // Search bar
              SizedBox(
                width: 220,
                height: 38,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF161E2E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm kênh...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 16),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 14),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Refresh Button
              TvFocusableCard(
                onTap: _isRefreshing
                    ? () {}
                    : () {
                        _loadChannels(forceRefresh: true, triggerServerFetch: true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đang làm mới danh sách kênh từ nguồn phát...'),
                            backgroundColor: Color(0xFF0284C7),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isRefreshing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF38BDF8),
                              ),
                            )
                          : const Icon(Icons.rotate_right_rounded, color: Color(0xFF38BDF8), size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'Làm mới',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Channels Grid (Full height!)
        Expanded(
          child: filteredChannels.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'Không tìm thấy kênh nào khớp với "$_searchQuery"'
                            : 'Không có kênh nào trong mục ${_getCategoryTitle(_selectedCategory)}.',
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : _buildTieredChannelGrid(filteredChannels, crossAxisCount),
        ),
      ],
    );
  }

  Widget _buildMobileContent(List<IptvSourceModel> sources, List<String> groups, List<IptvChannelModel> filteredChannels, int crossAxisCount) {
    return Column(
      children: [
        // Mobile Top Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.live_tv_rounded, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              const Text(
                'Truyền Hình',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TvFocusableCard(
                onTap: () => _showSourceSelectionDialog(sources),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  color: const Color(0xFF1E293B),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.playlist_play_rounded, color: Color(0xFF38BDF8), size: 16),
                      SizedBox(width: 4),
                      Text('Nguồn', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal Category Tabs
        _buildCategoryPills(),
        _buildGroupPills(groups),

        // Grid
        Expanded(
          child: filteredChannels.isEmpty
              ? Center(
                  child: Text(
                    'Không có kênh nào trong mục ${_getCategoryTitle(_selectedCategory)}.',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                )
              : _buildTieredChannelGrid(filteredChannels, crossAxisCount),
        ),
      ],
    );
  }

  Widget _buildCategoryPills() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: kIptvCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = kIptvCategories[index];
          final isSelected = _selectedCategory == cat.id;
          final count = _getCategoryCount(cat.id);

          Color activeColor = const Color(0xFF0284C7);
          Color activeBorder = const Color(0xFF38BDF8);
          Color countBadgeBg = const Color(0xFF075985);

          if (cat.id == 'FOOTBALL') {
            activeColor = const Color(0xFF059669);
            activeBorder = const Color(0xFF34D399);
            countBadgeBg = const Color(0xFF064E3B);
          } else if (cat.id == 'OTHER_SPORTS') {
            activeColor = const Color(0xFF7C3AED);
            activeBorder = const Color(0xFFA78BFA);
            countBadgeBg = const Color(0xFF4C1D95);
          } else if (cat.id == 'PINNED') {
            activeColor = const Color(0xFFD97706);
            activeBorder = const Color(0xFFF59E0B);
            countBadgeBg = const Color(0xFF78350F);
          } else if (cat.id == 'ALL') {
            activeColor = const Color(0xFF334155);
            activeBorder = const Color(0xFF64748B);
            countBadgeBg = const Color(0xFF1E293B);
          }

          return TvFocusableCard(
            onTap: () {
              setState(() {
                _selectedCategory = cat.id;
                _selectedGroup = 'ALL';
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : const Color(0xFF161E2E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? activeBorder : const Color(0xFF1E293B),
                  width: isSelected ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.icon,
                    size: 16,
                    color: isSelected ? Colors.white : Colors.white60,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    cat.title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected ? countBadgeBg : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? activeBorder.withOpacity(0.4) : const Color(0xFF334155),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGroupPills(List<String> groups) {
    if (groups.length <= 2) return const SizedBox.shrink();

    return Container(
      height: 40,
      padding: const EdgeInsets.only(bottom: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final group = groups[index];
          final isSelected = _selectedGroup == group;
          final isFav = group == '⭐ Yêu Thích';

          return TvFocusableCard(
            onTap: () {
              setState(() {
                _selectedGroup = group;
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? (isFav ? const Color(0xFFD97706) : const Color(0xFF0284C7))
                    : const Color(0xFF1E293B).withOpacity(0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? (isFav ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8))
                      : const Color(0xFF334155),
                  width: isSelected ? 1.2 : 0.8,
                ),
              ),
              child: Center(
                child: Text(
                  group == 'ALL' ? 'Tất cả nhóm' : group,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white60,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Builds a channel grid that splits FOOTBALL into Area 1 (Famous/VN) and Area 2 (Other)
  Widget _buildTieredChannelGrid(List<IptvChannelModel> channels, int crossAxisCount) {
    final bool isFootballTab = _selectedCategory == 'FOOTBALL';

    // For non-FOOTBALL tabs, render a simple flat grid
    if (!isFootballTab) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        addAutomaticKeepAlives: true,
        cacheExtent: 350,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.92,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          return _buildChannelCard(channels[index], channels);
        },
      );
    }

    // FOOTBALL tab: Split into Area 1 and Area 2
    final area1 = channels.where((c) => c.priorityLevel <= 2).toList();
    final area2 = channels.where((c) => c.priorityLevel > 2).toList();

    return CustomScrollView(
      cacheExtent: 350,
      slivers: [
        // Area 1: Famous / VN matches
        if (area1.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(
                    'Tâm Điểm & Giải Đấu Hàng Đầu',
                    style: TextStyle(
                      color: Colors.amber.shade300,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${area1.length}',
                      style: TextStyle(color: Colors.amber.shade300, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.92,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildChannelCard(area1[index], channels),
                childCount: area1.length,
                addAutomaticKeepAlives: true,
              ),
            ),
          ),
        ],

        // Area 2: Other matches
        if (area2.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  const Text('🌐', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  const Text(
                    'Các Trận Đấu & Giải Đấu Khác',
                    style: TextStyle(
                      color: Colors.white54,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${area2.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.92,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildChannelCard(area2[index], channels),
                childCount: area2.length,
                addAutomaticKeepAlives: true,
              ),
            ),
          ),
        ],

        // Bottom padding
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  Widget _buildChannelCard(IptvChannelModel channel, List<IptvChannelModel> currentList) {
    return TvFocusableCard(
      onTap: () => _playChannel(channel, currentList),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: channel.isPinned
              ? const Color(0xFF1E293B).withOpacity(0.9)
              : (channel.isFamous || channel.isVietnam)
                  ? const Color(0xFF0F1A33)
                  : const Color(0xFF161E2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: channel.isPinned
                ? const Color(0xFFF59E0B).withOpacity(0.6)
                : (channel.isVietnam)
                    ? const Color(0xFFEF4444).withOpacity(0.4)
                    : (channel.isFamous)
                        ? const Color(0xFF3B82F6).withOpacity(0.3)
                        : const Color(0xFF1E293B),
            width: channel.isPinned ? 1.5 : (channel.isFamous || channel.isVietnam) ? 1.2 : 1.0,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top Row: Badges (Pinned, Time, Live, Category)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (channel.isPinned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 12),
                        SizedBox(width: 2),
                        Text(
                          'GHIM',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (channel.displayTime.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.3), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_rounded, color: Color(0xFF38BDF8), size: 9),
                        const SizedBox(width: 3),
                        Text(
                          channel.displayTime,
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(width: 12),

                if (channel.isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4), width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.redAccent, size: 6),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (channel.category == 'OTHER_SPORTS')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Thể thao',
                      style: TextStyle(
                        color: Colors.purpleAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),

            const Spacer(),

            // Channel Logo (Optimized memory cache 64x64)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: channel.logo.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: channel.logo,
                        memCacheWidth: 80,
                        memCacheHeight: 80,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const Center(
                          child: Icon(Icons.live_tv_rounded, color: Colors.white24, size: 24),
                        ),
                        errorWidget: (context, url, error) => Center(
                          child: Text(
                            channel.name.isNotEmpty ? channel.name[0].toUpperCase() : 'TV',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        channel.name.isNotEmpty ? channel.name[0].toUpperCase() : 'TV',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
            ),

            const Spacer(),

            // Channel Name (Clean title, 2 lines)
            Text(
              channel.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 3),

            // Source & Group Label
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_selectedSourceId == 'ALL' && channel.sourceName.isNotEmpty) ...[
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3), width: 0.6),
                      ),
                      child: Text(
                        channel.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    channel.group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
