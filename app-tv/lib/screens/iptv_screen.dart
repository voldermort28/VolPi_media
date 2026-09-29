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

class _IptvScreenState extends State<IptvScreen> {
  List<IptvChannelModel> _allChannels = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
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

  List<String> _getAvailableGroups() {
    final Set<String> groups = {};
    for (final c in _allChannels) {
      if (_selectedSourceId == 'ALL' || c.sourceId == _selectedSourceId) {
        if (c.group.isNotEmpty) {
          groups.add(c.group);
        }
      }
    }
    final sorted = groups.toList()..sort();
    return ['ALL', '⭐ Yêu Thích', ...sorted];
  }

  List<IptvChannelModel> _getFilteredChannels() {
    return _allChannels.where((c) {
      // 1. Source / Playlist filter
      if (_selectedSourceId != 'ALL' && c.sourceId != _selectedSourceId) {
        return false;
      }

      // 2. Group filter
      if (_selectedGroup == '⭐ Yêu Thích') {
        if (!c.isPinned) return false;
      } else if (_selectedGroup != 'ALL') {
        if (c.group != _selectedGroup) return false;
      }

      // 3. Search query filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = c.name.toLowerCase().contains(q);
        final groupMatch = c.group.toLowerCase().contains(q);
        final sourceMatch = c.sourceName.toLowerCase().contains(q);
        if (!nameMatch && !groupMatch && !sourceMatch) return false;
      }

      return true;
    }).toList();
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
          mainAxisAlignment: MainCrossAxisAlignment.center,
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
            mainAxisAlignment: MainCrossAxisAlignment.center,
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
        final bool isLargeScreen = constraints.maxWidth >= 900;
        final bool isMediumScreen = constraints.maxWidth >= 600 && constraints.maxWidth < 900;

        int crossAxisCount = 2;
        if (isLargeScreen) {
          crossAxisCount = 5;
        } else if (isMediumScreen) {
          crossAxisCount = 3;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: Column(
            children: [
              // Top Bar: Title, Source Dropdown Menu, Search, Refresh Button
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF1E293B), width: 1.2)),
                ),
                child: Row(
                  children: [
                    // Header title & count
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.live_tv_rounded, color: Color(0xFF38BDF8), size: 22),
                              const SizedBox(width: 8),
                              const Text(
                                'Truyền Hình (IPTV)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
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
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Đồng bộ tức thì từ stremio.laboon.vn • D-pad Lên/Xuống để chuyển kênh',
                            style: TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    // DROPDOWN MENU: BỘ LỌC THEO NGUỒN LINK PLAYLIST
                    TvFocusableCard(
                      onTap: () => _showSourceSelectionDialog(sources),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 38,
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _selectedSourceId != 'ALL'
                              ? const Color(0xFF0284C7).withOpacity(0.2)
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedSourceId != 'ALL'
                                ? const Color(0xFF38BDF8)
                                : const Color(0xFF334155),
                            width: _selectedSourceId != 'ALL' ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedSourceId != 'ALL' ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
                              color: const Color(0xFF38BDF8),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: isLargeScreen ? 160 : 110),
                              child: Text(
                                currentSource.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 20),
                          ],
                        ),
                      ),
                    ),

                    // Search Field (Large & Medium screen)
                    if (constraints.maxWidth >= 680)
                      Container(
                        width: 200,
                        height: 38,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
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

                    // Refresh Button (1-click sync from server)
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

              // Group Filter Pills
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isFav ? const Color(0xFFD97706) : const Color(0xFF0284C7))
                              : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? (isFav ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8))
                                : const Color(0xFF334155),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            group == 'ALL' ? 'Tất Cả' : group,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Channels Grid
              Expanded(
                child: filteredChannels.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainCrossAxisAlignment.center,
                          children: [
                            const Icon(Icons.tv_off_rounded, color: Colors.white24, size: 56),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'Không tìm thấy kênh nào khớp với "$_searchQuery"'
                                  : 'Không có kênh nào trong mục này.',
                              style: const TextStyle(color: Colors.white60, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 1.15,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: filteredChannels.length,
                        itemBuilder: (context, index) {
                          final channel = filteredChannels[index];
                          return _buildChannelCard(channel, filteredChannels);
                        },
                      ),
              ),
            ],
          ),
        );
      },
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
              : const Color(0xFF161E2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: channel.isPinned ? const Color(0xFFF59E0B).withOpacity(0.6) : const Color(0xFF1E293B),
            width: channel.isPinned ? 1.5 : 1.0,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Top Row: Pinned badge or Live indicator
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
                else
                  const SizedBox(width: 12),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
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
                ),
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

            // Channel Name
            Text(
              channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
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
