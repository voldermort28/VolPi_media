import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/match_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class FootballScreen extends StatefulWidget {
  final ApiService apiService;
  final String source;
  final String title;
  final bool isActive;

  const FootballScreen({
    super.key,
    required this.apiService,
    this.source = 'xoilac',
    this.title = 'Xôi Lạc TV',
    this.isActive = false,
  });

  @override
  FootballScreenState createState() => FootballScreenState();
}

class FootballScreenState extends State<FootballScreen> {
  Future<void> reloadMatches() => _loadMatches(forceRefresh: true);

  List<MatchModel> _matches = [];
  List<MatchModel> _majorMatches = [];
  List<MatchModel> _otherOngoingMatches = [];
  List<MatchModel> _upcomingOtherMatches = [];
  List<MatchModel> _finishedMatches = [];
  bool _isLoading = true;
  String? _errorMessage;
  final FocusNode _firstMatchFocusNode = FocusNode();
  FocusNode get firstMatchFocusNode => _firstMatchFocusNode;

  String _selectedFilterId = 'all';

  final List<Map<String, String>> _leagueFilters = const [
    {'id': 'all', 'label': 'Tất cả'},
    {'id': 'major', 'label': '⭐ Tâm Điểm'},
    {'id': 'live', 'label': '🔴 Đang Đá'},
    {'id': 'epl', 'label': '🏴󠁧󠁢󠁥󠁮󠁧󠁿 Ngoại Hạng Anh'},
    {'id': 'c1', 'label': '🏆 Cúp C1'},
    {'id': 'laliga', 'label': '🇪🇸 La Liga'},
    {'id': 'seriea', 'label': '🇮🇹 Serie A'},
    {'id': 'bundesliga', 'label': '🇩🇪 Bundesliga'},
    {'id': 'vietnam', 'label': '🇻🇳 Việt Nam'},
    {'id': 'finished', 'label': '🏁 Đã Xong'},
  ];

  bool _matchPassesFilter(MatchModel m, String filterId) {
    if (filterId == 'all') return true;
    if (filterId == 'major') {
      return !m.isFinishedMatch &&
          (m.isFamous || m.isVietnam || m.isFavorite || m.isHot || m.isPremierLeagueOrC1);
    }
    if (filterId == 'live') {
      return m.isOngoingNow && !m.isFinishedMatch;
    }
    if (filterId == 'finished') {
      return m.isFinishedMatch;
    }
    final leagueLower = m.league.toLowerCase();
    if (filterId == 'epl') {
      if (leagueLower.contains('ngoại hạng anh') ||
          leagueLower.contains('english premier league') ||
          leagueLower.contains('epl')) {
        return true;
      }
      if (leagueLower.contains('premier league') || leagueLower.contains('ngoại hạng')) {
        final otherLeagues = [
          'kuwait', 'ai cập', 'egypt', 'belarus', 'nga', 'russia',
          'scotland', 'israel', 'ukraine', 'ireland', 'wales', 'canada',
          'úc', 'australia', 'kazakhstan', 'singapore', 'thái', 'thai',
          'indo', 'ấn độ', 'india', 'nam phi', 'hàn quốc', 'korea', 'qatar',
          'uae', 'saudi', 'iraq', 'armenia', 'georgia', 'azerbaijan'
        ];
        return !otherLeagues.any((c) => leagueLower.contains(c));
      }
      if (leagueLower.contains('premier') && (leagueLower.contains('anh') || leagueLower.contains('england'))) {
        return true;
      }
      return false;
    }
    if (filterId == 'c1') {
      final bool isOtherConfederation = leagueLower.contains('caf') ||
          leagueLower.contains('africa') ||
          leagueLower.contains('châu phi') ||
          leagueLower.contains('concacaf') ||
          leagueLower.contains('bắc mỹ') ||
          leagueLower.contains('afc') ||
          leagueLower.contains('châu á') ||
          leagueLower.contains('ofc') ||
          leagueLower.contains('nữ') ||
          leagueLower.contains('women') ||
          leagueLower.contains('u19') ||
          leagueLower.contains('u21') ||
          leagueLower.contains('youth');

      if (isOtherConfederation) return false;

      return leagueLower.contains('uefa champions') ||
          leagueLower.contains('cúp c1') ||
          leagueLower.contains('c1 châu âu') ||
          leagueLower.contains('ucl') ||
          leagueLower.contains('champions league') ||
          RegExp(r'(^|[\s\[(])c1([\s\])]|$)').hasMatch(leagueLower);
    }
    if (filterId == 'laliga') {
      return (leagueLower.contains('la liga') ||
              leagueLower.contains('laliga') ||
              leagueLower.contains('tây ban nha')) &&
          !leagueLower.contains('hạng 2') &&
          !leagueLower.contains('segunda');
    }
    if (filterId == 'seriea') {
      return (leagueLower.contains('serie a') ||
              leagueLower.contains('vđqg ý') ||
              leagueLower.contains('italia') ||
              leagueLower.contains('vđqg italia')) &&
          !leagueLower.contains('serie b') &&
          !leagueLower.contains('hạng 2');
    }
    if (filterId == 'bundesliga') {
      return (leagueLower.contains('bundesliga') ||
              leagueLower.contains('vđqg đức')) &&
          !leagueLower.contains('bundesliga 2') &&
          !leagueLower.contains('2. bundesliga') &&
          !leagueLower.contains('hạng 2');
    }
    if (filterId == 'vietnam') {
      return m.isVietnam ||
          leagueLower.contains('v-league') ||
          leagueLower.contains('vleague') ||
          leagueLower.contains('v.league') ||
          leagueLower.contains('việt nam');
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadMatches(forceRefresh: true);
  }

  @override
  void didUpdateWidget(covariant FootballScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadMatches(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _firstMatchFocusNode.dispose();
    super.dispose();
  }

  void _computeCategorizedMatches() {
    final major = _matches
        .where((m) =>
            !m.isFinishedMatch &&
            (m.isFamous || m.isVietnam || m.isFavorite || m.isHot || m.isPremierLeagueOrC1))
        .toList();

    major.sort((a, b) {
      final aPlC1 = a.isPremierLeagueOrC1;
      final bPlC1 = b.isPremierLeagueOrC1;
      if (aPlC1 != bPlC1) {
        return aPlC1 ? -1 : 1;
      }
      if (a.isOngoingNow != b.isOngoingNow) {
        return a.isOngoingNow ? -1 : 1;
      }
      return a.matchTimestamp.compareTo(b.matchTimestamp);
    });

    _majorMatches = major;

    _otherOngoingMatches = _matches
        .where((m) =>
            m.isOngoingNow &&
            !m.isFinishedMatch &&
            !m.isFamous &&
            !m.isVietnam &&
            !m.isFavorite &&
            !m.isHot &&
            !m.isPremierLeagueOrC1)
        .toList();

    _upcomingOtherMatches = _matches
        .where((m) =>
            !m.isOngoingNow &&
            !m.isFinishedMatch &&
            !m.isFamous &&
            !m.isVietnam &&
            !m.isFavorite &&
            !m.isHot &&
            !m.isPremierLeagueOrC1)
        .toList();

    _finishedMatches = _matches.where((m) => m.isFinishedMatch).toList();
  }

  Future<void> _loadMatches({bool forceRefresh = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await widget.apiService.getLiveMatches(
        forceRefresh: forceRefresh,
        source: widget.source,
      );
      if (mounted) {
        setState(() {
          _matches = results.where((m) => !m.isEsports).toList();
          _computeCategorizedMatches();
          _isLoading = false;
        });

        // Tự động nhảy tới ngay trận đấu đang diễn ra đầu tiên khi danh sách load xong
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _matches.isNotEmpty) {
            _firstMatchFocusNode.requestFocus();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể tải lịch thi đấu: ${e.toString()}';
        });
      }
    }
  }

  void _onMatchSelected(MatchModel match) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
      ),
    );

    final streams = await widget.apiService.getMatchStreams(
      match.id,
      source: widget.source,
    );
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading dialog

    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có luồng phát sóng cho trận này hoặc trận chưa diễn ra.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // Tự động chọn luồng stream đầu tiên để phát ngay mà không cần hỏi (giống bên tab phim)
    _playStream(match, streams[0], streams);
  }

  void _showChannelSelector(MatchModel match, List<StreamChannel> channels) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${match.homeTeam} vs ${match.awayTeam}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Chọn kênh bình luận viên để xem trực tiếp:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: channels.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final ch = channels[idx];
                    return TvFocusableCard(
                      autoFocus: idx == 0,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _playStream(match, ch, channels);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        color: const Color(0xFF1E293B),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_fill, color: Color(0xFF38BDF8), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                ch.title,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: Colors.white38),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _playStream(MatchModel match, StreamChannel channel, List<StreamChannel> allChannels) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: channel.url,
          title: '${match.homeTeam} vs ${match.awayTeam}',
          subtitle: '${channel.title} • ${match.league}',
          headers: channel.headers,
          availableChannels: allChannels,
          isLive: true,
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final bool isDrawerMode = Platform.isIOS || MediaQuery.of(context).size.width < 750;
    final bool isMobile = MediaQuery.of(context).size.width < 700;

    return Column(
      children: [
        // Action Bar (Header row in FootballScreen)
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 8 : 20,
            vertical: isMobile ? 6 : 10,
          ),
          child: Row(
            children: [
              Text('⚽', style: TextStyle(fontSize: isMobile ? 16 : 20)),
              SizedBox(width: isMobile ? 6 : 8),
              Flexible(
                child: Text(
                  '${widget.title} - Trực Tiếp Hôm Nay',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 14.5 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (_matches.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 6 : 8,
                    vertical: isMobile ? 1.5 : 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                  ),
                  child: Text(
                    '${_matches.length} trận',
                    style: TextStyle(
                      color: const Color(0xFF38BDF8),
                      fontSize: isMobile ? 10 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // On TV / large desktop without top mobile header, keep a focusable refresh button on the right
              if (!isDrawerMode) ...[
                const Spacer(),
                SizedBox(
                  height: 38,
                  child: TvFocusableCard(
                    onTap: () => _loadMatches(forceRefresh: true),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: const Color(0xFF1E293B),
                      child: const Row(
                        children: [
                          Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Làm Mới',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // League Filter Chips Bar
        SizedBox(
          height: isMobile ? 32 : 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 20),
            itemCount: _leagueFilters.length,
            itemBuilder: (context, idx) {
              final filter = _leagueFilters[idx];
              final isSelected = filter['id'] == _selectedFilterId;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TvFocusableCard(
                  onTap: () {
                    setState(() {
                      _selectedFilterId = filter['id']!;
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  focusBorderColor: const Color(0xFF38BDF8),
                  scale: 1.05,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 10 : 14,
                      vertical: isMobile ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF38BDF8) : Colors.white12,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      filter['label']!,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: isMobile ? 4 : 8),

        // Main List or Loading / Error
        Expanded(
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF38BDF8)),
                      SizedBox(height: 14),
                      Text('Đang cập nhật lịch đấu mới nhất...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 48),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 16),
                          TvFocusableCard(
                            onTap: () => _loadMatches(forceRefresh: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: const Color(0xFF38BDF8),
                              child: const Text('Thử lại', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadMatches(forceRefresh: true),
                      color: const Color(0xFF38BDF8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Grid columns adaptive: Widescreen >=1200 (4 cols), Tablet/TV >=720 (3 cols), Phone & Window >=360 (2 cols), Ultra-narrow <360 (1 col)
                          int crossAxisCount = 1;
                          if (constraints.maxWidth >= 1200) {
                            crossAxisCount = 4;
                          } else if (constraints.maxWidth >= 720) {
                            crossAxisCount = 3;
                          } else if (constraints.maxWidth >= 360) {
                            crossAxisCount = 2;
                          }

                          final major = _majorMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList();
                          final ongoing = _otherOngoingMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList();
                          final others = _upcomingOtherMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList();
                          final finished = _finishedMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList();

                          return CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            cacheExtent: 350,
                            slivers: [
                              // Khu vực 1: ⭐ Tâm Điểm & Giải Đấu Hàng Đầu (Lên đầu tiên)
                              if (major.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '⭐ Tâm Điểm & Giải Đấu Hàng Đầu',
                                    count: major.length.toString(),
                                    color: const Color(0xFFF59E0B),
                                    subtitle: 'Trận Hot • Việt Nam • Ngoại Hạng Anh • Cúp C1 • La Liga • Serie A • Bundesliga...',
                                    isMobile: isMobile,
                                  ),
                                ),
                                _buildMatchGrid(major, crossAxisCount, isFirstSection: true, isMobile: isMobile),
                              ],

                              // Khu vực 2: 🔴 Đang Diễn Ra (Trong 90') - Dưới nhóm tâm điểm
                              if (ongoing.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '🔴 Đang Diễn Ra (Trong 90\')',
                                    count: ongoing.length.toString(),
                                    color: const Color(0xFFEF4444),
                                    subtitle: 'Các trận đấu đang trực tiếp thi đấu trên sân cỏ ngay lúc này',
                                    isMobile: isMobile,
                                  ),
                                ),
                                _buildMatchGrid(ongoing, crossAxisCount, isFirstSection: major.isEmpty, isMobile: isMobile),
                              ],

                              // Khu vực 3: 🌐 Các Trận Đấu & Giải Đấu Khác (Sắp diễn ra)
                              if (others.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '🌐 Các Trận Đấu & Giải Đấu Khác',
                                    count: others.length.toString(),
                                    color: const Color(0xFF38BDF8),
                                    subtitle: 'Các giải đấu phụ và trận đấu sắp diễn ra hôm nay',
                                    isMobile: isMobile,
                                  ),
                                ),
                                _buildMatchGrid(others, crossAxisCount, isFirstSection: major.isEmpty && ongoing.isEmpty, isMobile: isMobile),
                              ],

                              // Khu vực 4: 🏁 Trận Đấu Đã Kết Thúc (đặt ở cuối cùng để không chắn trận mới)
                              if (finished.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '🏁 Trận Đấu Đã Kết Thúc',
                                    count: finished.length.toString(),
                                    color: const Color(0xFF64748B),
                                    subtitle: 'Các trận đấu đã diễn ra hơn 90-100 phút trước',
                                    isMobile: isMobile,
                                  ),
                                ),
                                _buildMatchGrid(finished, crossAxisCount, isFirstSection: false, isMobile: isMobile),
                              ],

                              // Fallback nếu không chia được mục nào hoặc lọc không có trận
                              if (major.isEmpty && ongoing.isEmpty && others.isEmpty && finished.isEmpty && _matches.isNotEmpty) ...[
                                if (_selectedFilterId == 'all') ...[
                                  SliverToBoxAdapter(
                                    child: _buildSectionHeader(
                                      title: '⚽ Tất Cả Trận Đấu Hôm Nay',
                                      count: _matches.length.toString(),
                                      color: const Color(0xFF38BDF8),
                                      isMobile: isMobile,
                                    ),
                                  ),
                                  _buildMatchGrid(_matches, crossAxisCount, isFirstSection: true, isMobile: isMobile),
                                ] else ...[
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.sports_soccer_outlined, color: Colors.white24, size: 48),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Không có trận đấu nào thuộc giải này hôm nay.',
                                            style: TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                          const SizedBox(height: 14),
                                          TvFocusableCard(
                                            onTap: () {
                                              setState(() {
                                                _selectedFilterId = 'all';
                                              });
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                              color: const Color(0xFF0284C7),
                                              child: const Text('Xem tất cả trận đấu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],

                              const SliverToBoxAdapter(
                                child: SizedBox(height: 24),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String count,
    required Color color,
    String? subtitle,
    bool isMobile = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 8 : 20,
        isMobile ? 8 : 14,
        isMobile ? 8 : 20,
        isMobile ? 4 : 8,
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 3 : 4,
            height: isMobile ? 14 : 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: isMobile ? 6 : 8),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 13 : 15,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 5 : 7,
              vertical: isMobile ? 1.5 : 2,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.6), width: 0.8),
            ),
            child: Text(
              '$count trận',
              style: TextStyle(color: color, fontSize: isMobile ? 9 : 10, fontWeight: FontWeight.bold),
            ),
          ),
          if (subtitle != null && !isMobile) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchGrid(List<MatchModel> matches, int crossAxisCount, {bool isFirstSection = false, bool isMobile = false}) {
    final double extent = isMobile ? 106.0 : 136.0;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: isMobile ? 6 : 14,
          mainAxisSpacing: isMobile ? 6 : 14,
          mainAxisExtent: extent,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, idx) => _buildMatchCard(
            matches[idx],
            isMobile: isMobile,
            focusNode: (isFirstSection && idx == 0) ? _firstMatchFocusNode : null,
          ),
          childCount: matches.length,
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: true,
        ),
      ),
    );
  }

  Widget _buildMatchCard(MatchModel match, {bool isMobile = false, FocusNode? focusNode}) {
    final bool isOngoing = match.isOngoingNow;
    final bool isLiveBadge = isOngoing || match.isLive;

    Color cardBg = const Color(0xFF1E293B);
    Color borderColor = const Color(0xFF334155);
    Color focusBorder = const Color(0xFF38BDF8);

    if (isOngoing) {
      cardBg = const Color(0xFF3F0B18).withOpacity(0.85);
      borderColor = const Color(0xFFE11D48);
      focusBorder = const Color(0xFFF43F5E);
    } else if (match.isVietnam) {
      cardBg = const Color(0xFF500724).withOpacity(0.7);
      borderColor = const Color(0xFFDC2626);
      focusBorder = const Color(0xFFFDE047);
    } else if (match.isMuFavorite) {
      cardBg = const Color(0xFF450A0A).withOpacity(0.7);
      borderColor = const Color(0xFF991B1B);
      focusBorder = const Color(0xFFEF4444);
    } else if (match.isFavorite) {
      cardBg = const Color(0xFF422006).withOpacity(0.7);
      borderColor = const Color(0xFFB45309);
      focusBorder = const Color(0xFFF59E0B);
    } else if (match.isFamous) {
      cardBg = const Color(0xFF0C2444).withOpacity(0.6);
      borderColor = const Color(0xFF0284C7);
      focusBorder = const Color(0xFF38BDF8);
    } else if (match.isHot) {
      cardBg = const Color(0xFF312E81).withOpacity(0.5);
      borderColor = const Color(0xFF4F46E5);
      focusBorder = const Color(0xFF818CF8);
    } else if (match.isFinishedMatch) {
      cardBg = const Color(0xFF0F172A).withOpacity(0.6);
      borderColor = const Color(0xFF1E293B);
      focusBorder = const Color(0xFF64748B);
    }

    final double footerFontSize = isMobile ? 8.0 : 10.0;
    Widget footerWidget;
    if (isOngoing) {
      footerWidget = Text(
        isMobile ? '🔴 ĐANG TRỰC TIẾP' : '🔴 ĐANG THI ĐẤU TRỰC TIẾP (TRONG 90\') 🔴',
        style: TextStyle(color: const Color(0xFFF43F5E), fontSize: footerFontSize, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (match.isVietnam) {
      footerWidget = Text(
        '⭐ BÓNG ĐÁ VIỆT NAM ⭐',
        style: TextStyle(color: const Color(0xFFFDE047), fontSize: footerFontSize, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (match.isMuFavorite) {
      footerWidget = Text(
        '⭐ MANCHESTER UNITED ⭐',
        style: TextStyle(color: const Color(0xFFFDE047), fontSize: footerFontSize, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (match.isFavorite && match.favoriteBadgeText.isNotEmpty) {
      footerWidget = Text(
        '⭐ TÂM ĐIỂM: ${match.favoriteBadgeText} ⭐',
        style: TextStyle(color: const Color(0xFFFDBA74), fontSize: footerFontSize, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (match.isFamous) {
      footerWidget = Text(
        '🔥 ${match.league.toUpperCase()} 🔥',
        style: TextStyle(color: const Color(0xFF38BDF8), fontSize: footerFontSize, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (match.isHot) {
      footerWidget = Text(
        '🔥 TRẬN ĐẤU TÂM ĐIỂM 🔥',
        style: TextStyle(color: const Color(0xFFFDBA74), fontSize: footerFontSize, fontWeight: FontWeight.bold),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (match.isFinishedMatch) {
      footerWidget = Text(
        isMobile ? 'Đã kết thúc' : 'Đã thi đấu xong • Xem lại diễn biến',
        style: TextStyle(color: const Color(0xFF64748B), fontSize: footerFontSize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      footerWidget = Text(
        isMobile ? 'BL Tiếng Việt • HD' : 'Bình luận tiếng Việt • Full HD',
        style: TextStyle(color: const Color(0xFF64748B), fontSize: footerFontSize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final double logoSize = isMobile ? 20.0 : 28.0;

    return TvFocusableCard(
      focusNode: focusNode,
      onTap: () => _onMatchSelected(match),
      focusBorderColor: focusBorder,
      borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
          border: Border.all(color: borderColor, width: 1),
        ),
        padding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header: League & Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    match.league,
                    style: TextStyle(
                      color: const Color(0xFF94A3B8),
                      fontSize: isMobile ? 9.5 : 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 4 : 8,
                    vertical: isMobile ? 1.5 : 3,
                  ),
                  decoration: BoxDecoration(
                    color: isLiveBadge ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF0284C7).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(isMobile ? 4 : 6),
                    border: Border.all(
                      color: isLiveBadge ? Colors.redAccent.withOpacity(0.6) : const Color(0xFF38BDF8).withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isLiveBadge ? Icons.fiber_manual_record : (match.isFinishedMatch ? Icons.check_circle_outline_rounded : Icons.access_time_rounded),
                        color: isLiveBadge ? Colors.redAccent : (match.isFinishedMatch ? const Color(0xFF94A3B8) : const Color(0xFF38BDF8)),
                        size: isMobile ? 8.0 : 10,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isOngoing ? 'TRỰC TIẾP • ${match.liveMinuteLabel}' : (match.isLive ? 'TRỰC TIẾP' : (match.isFinishedMatch ? 'HẾT GIỜ' : match.time)),
                        style: TextStyle(
                          color: isLiveBadge ? Colors.redAccent : (match.isFinishedMatch ? const Color(0xFF94A3B8) : const Color(0xFF38BDF8)),
                          fontSize: isMobile ? 8.5 : 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Teams Stacked Rows (Home & Away each get full width)
            Column(
              children: [
                // Home Team
                Row(
                  children: [
                    _buildTeamLogo(match.homeLogo, teamName: match.homeTeam, size: logoSize),
                    SizedBox(width: isMobile ? 5 : 8),
                    Expanded(
                      child: Text(
                        match.homeTeam,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 11.5 : 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 3 : 5,
                        vertical: isMobile ? 1 : 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Chủ',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: isMobile ? 8.0 : 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 2.5 : 6),
                // Away Team
                Row(
                  children: [
                    _buildTeamLogo(match.awayLogo, teamName: match.awayTeam, size: logoSize),
                    SizedBox(width: isMobile ? 5 : 8),
                    Expanded(
                      child: Text(
                        match.awayTeam,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 11.5 : 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 3 : 5,
                        vertical: isMobile ? 1 : 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Khách',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: isMobile ? 8.0 : 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Footer Tags (MU / Vietnam / Favorite / Normal)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: footerWidget),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamLogo(String url, {String teamName = '', double size = 30}) {
    final String initial = teamName.trim().isNotEmpty ? teamName.trim().substring(0, 1).toUpperCase() : '?';

    Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF334155),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontSize: size * 0.45, fontWeight: FontWeight.bold),
      ),
    );

    if (url.isEmpty || !url.startsWith('http')) {
      return placeholder;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          memCacheWidth: 64,
          memCacheHeight: 64,
          maxWidthDiskCache: 120,
          maxHeightDiskCache: 120,
          fit: BoxFit.contain,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
