import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/match_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../widgets/netflix/netflix_scrollable_row.dart';
import '../player/video_player_screen.dart';

class FootballAggregateScreen extends StatefulWidget {
  final ApiService apiService;
  final String title;
  final bool isActive;

  const FootballAggregateScreen({
    super.key,
    required this.apiService,
    this.title = 'Tổng Hợp Bóng Đá',
    this.isActive = false,
  });

  @override
  FootballAggregateScreenState createState() => FootballAggregateScreenState();
}

class FootballAggregateScreenState extends State<FootballAggregateScreen> {
  Future<void> reloadMatches() => _loadAllMatches(forceRefresh: true);

  List<MatchModel> _gavangMatches = [];
  List<MatchModel> _veboMatches = [];
  List<MatchModel> _socoliveMatches = [];
  bool _isLoading = true;
  String? _errorMessage;

  final FocusNode _firstCardFocusNode = FocusNode();
  FocusNode get firstMatchFocusNode => _firstCardFocusNode;

  String _selectedFilterId = 'all';

  final List<Map<String, String>> _leagueFilters = const [
    {'id': 'all', 'label': 'Tất cả'},
    {'id': 'major', 'label': '⭐ Tâm Điểm & MU/VN'},
    {'id': 'live', 'label': '🔴 Đang Đá'},
    {'id': 'epl', 'label': '🏴󠁧󠁢󠁥󠁮󠁧󠁿 Ngoại Hạng Anh'},
    {'id': 'c1', 'label': '🏆 Cúp C1'},
    {'id': 'vietnam', 'label': '🇻🇳 Việt Nam'},
    {'id': 'finished', 'label': '🏁 Đã Xong'},
  ];

  @override
  void initState() {
    super.initState();
    _loadAllMatches(forceRefresh: true);
  }

  @override
  void didUpdateWidget(covariant FootballAggregateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadAllMatches(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    _firstCardFocusNode.dispose();
    super.dispose();
  }

  bool _matchPassesFilter(MatchModel m, String filterId) {
    if (filterId == 'all') return true;
    if (filterId == 'major') {
      return !m.isFinishedMatch &&
          (m.isFamous || m.isVietnam || m.isMuFavorite || m.isFavorite || m.isHot || m.isPremierLeagueOrC1);
    }
    if (filterId == 'live') {
      return m.isOngoingNow && !m.isFinishedMatch;
    }
    if (filterId == 'finished') {
      return m.isFinishedMatch;
    }
    if (filterId == 'epl') {
      return m.isPremierLeagueOrC1 &&
          (m.league.toLowerCase().contains('premier') || m.league.toLowerCase().contains('ngoại hạng') || m.league.toLowerCase().contains('epl'));
    }
    if (filterId == 'c1') {
      return m.isPremierLeagueOrC1 &&
          (m.league.toLowerCase().contains('champions') || m.league.toLowerCase().contains('cúp c1') || m.league.toLowerCase().contains('ucl'));
    }
    if (filterId == 'vietnam') {
      return m.isVietnam;
    }
    return true;
  }

  Future<void> _loadAllMatches({bool forceRefresh = true}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        widget.apiService.getLiveMatches(forceRefresh: forceRefresh, source: 'gavang').catchError((_) => <MatchModel>[]),
        widget.apiService.getLiveMatches(forceRefresh: forceRefresh, source: 'vebo').catchError((_) => <MatchModel>[]),
        widget.apiService.getLiveMatches(forceRefresh: forceRefresh, source: 'socolive').catchError((_) => <MatchModel>[]),
      ]);

      if (!mounted) return;

      final gv = results[0].where((m) => !m.isEsports).toList();
      final vb = results[1].where((m) => !m.isEsports).toList();
      final sc = results[2].where((m) => !m.isEsports).toList();

      MatchModel.sortByPriority(gv);
      MatchModel.sortByPriority(vb);
      MatchModel.sortByPriority(sc);

      setState(() {
        _gavangMatches = gv;
        _veboMatches = vb;
        _socoliveMatches = sc;
        _isLoading = false;
      });

      // Tự động focus vào thẻ trận đầu tiên cho Remote TV
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_gavangMatches.isNotEmpty || _veboMatches.isNotEmpty || _socoliveMatches.isNotEmpty)) {
          _firstCardFocusNode.requestFocus();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể tải lịch thi đấu tổng hợp: ${e.toString()}';
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
      source: match.source,
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

    _playStream(match, streams[0], streams);
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

    final totalCount = _gavangMatches.length + _veboMatches.length + _socoliveMatches.length;

    return Column(
      children: [
        // Top Action Header
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: isMobile ? 8 : 12,
          ),
          child: Row(
            children: [
              Text('⚽', style: TextStyle(fontSize: isMobile ? 18 : 22)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 15 : 19,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (totalCount > 0)
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
                    '$totalCount trận',
                    style: TextStyle(
                      color: const Color(0xFF38BDF8),
                      fontSize: isMobile ? 10 : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              if (!isDrawerMode) ...[
                const Spacer(),
                SizedBox(
                  height: 38,
                  child: TvFocusableCard(
                    onTap: () => _loadAllMatches(forceRefresh: true),
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

        // Filter Chips Bar
        SizedBox(
          height: isMobile ? 32 : 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
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
        SizedBox(height: isMobile ? 8 : 12),

        // Main Content Rows
        Expanded(
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF38BDF8)),
                      SizedBox(height: 14),
                      Text('Đang tổng hợp lịch đấu từ Gà Vàng, Về Bờ & Socolive...', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                            onTap: () => _loadAllMatches(forceRefresh: true),
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
                      onRefresh: () => _loadAllMatches(forceRefresh: true),
                      color: const Color(0xFF38BDF8),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: isMobile ? 24 : 36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. GÀ VÀNG TV ROW
                            _buildSourceCategorySection(
                              title: 'Gà Vàng TV',
                              badgeText: 'gavang1.xyz',
                              iconEmoji: '🐓',
                              accentColor: const Color(0xFFF59E0B),
                              matches: _gavangMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList(),
                              isFirstCategory: true,
                              isMobile: isMobile,
                            ),
                            const SizedBox(height: 20),

                            // 2. VỀ BỜ TV ROW
                            _buildSourceCategorySection(
                              title: 'Về Bờ TV',
                              badgeText: 'vebozbn.cc',
                              iconEmoji: '⛵',
                              accentColor: const Color(0xFF0284C7),
                              matches: _veboMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList(),
                              isFirstCategory: false,
                              isMobile: isMobile,
                            ),
                            const SizedBox(height: 20),

                            // 3. SOCOLIVE TV ROW
                            _buildSourceCategorySection(
                              title: 'Socolive TV',
                              badgeText: 'socolive2.top',
                              iconEmoji: '⚡',
                              accentColor: const Color(0xFF10B981),
                              matches: _socoliveMatches.where((m) => _matchPassesFilter(m, _selectedFilterId)).toList(),
                              isFirstCategory: false,
                              isMobile: isMobile,
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSourceCategorySection({
    required String title,
    required String badgeText,
    required String iconEmoji,
    required Color accentColor,
    required List<MatchModel> matches,
    required bool isFirstCategory,
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header Row
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 6),
          child: Row(
            children: [
              Text(iconEmoji, style: TextStyle(fontSize: isMobile ? 18 : 20)),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMobile ? 14 : 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accentColor.withOpacity(0.5), width: 0.8),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${matches.length} trận)',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),

        // Horizontal Matches Row
        if (matches.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24, vertical: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white38, size: 16),
                  SizedBox(width: 8),
                  Text('Không có trận đấu nào phù hợp với bộ lọc hiện tại.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          _buildHorizontalRow(matches, isFirstCategory: isFirstCategory, isMobile: isMobile),
      ],
    );
  }

  Widget _buildHorizontalRow(List<MatchModel> matches, {required bool isFirstCategory, required bool isMobile}) {
    final double cardWidth = isMobile ? 200 : 255;
    final double rowHeight = isMobile ? 116 : 158;

    return NetflixScrollableRow(
      height: rowHeight,
      itemCount: matches.length,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 24),
      itemBuilder: (context, idx) {
        final match = matches[idx];
        final bool isFirstMatch = isFirstCategory && idx == 0;

        Color borderColor = Colors.transparent;
        String? badgeLabel;
        Color badgeColor = Colors.transparent;

        if (match.isMuFavorite) {
          borderColor = const Color(0xFFDC2626); // MU Red
          badgeLabel = '👹 MAN UNITED';
          badgeColor = const Color(0xFFDC2626);
        } else if (match.isVietnam) {
          borderColor = const Color(0xFFEAB308); // VN Gold
          badgeLabel = '🇻🇳 VIỆT NAM';
          badgeColor = const Color(0xFFEAB308);
        } else if (match.isPremierLeagueOrC1) {
          borderColor = const Color(0xFF38BDF8); // EPL / C1 Blue
          badgeLabel = match.league.toLowerCase().contains('champions') || match.league.toLowerCase().contains('c1')
              ? '🏆 C1 CHÂU ÂU'
              : '🏴󠁧󠁢󠁥󠁮󠁧󠁿 NGOẠI HẠNG';
          badgeColor = const Color(0xFF0284C7);
        } else if (match.isHot) {
          borderColor = const Color(0xFFF59E0B);
          badgeLabel = '🔥 TRẬN HOT';
          badgeColor = const Color(0xFFD97706);
        } else if (match.isOngoingNow) {
          borderColor = const Color(0xFFE50914);
        }

        return RepaintBoundary(
          child: TvFocusableCard(
            focusNode: isFirstMatch ? _firstCardFocusNode : null,
            onTap: () => _onMatchSelected(match),
            borderRadius: BorderRadius.circular(6),
            scale: 1.05,
            focusBorderColor: Colors.white,
            child: Container(
              width: cardWidth,
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 10 : 12,
                vertical: isMobile ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color: borderColor,
                    width: 3.5,
                  ),
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                  right: BorderSide(color: Colors.white.withOpacity(0.06)),
                  bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Row 1: League & Status Badges
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          match.league,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isMobile ? 10 : 11,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (match.isOngoingNow)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),

                  // Row 2: Teams & Logos
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        // Home Team
                        Row(
                          children: [
                            if (match.homeLogo.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: match.homeLogo,
                                width: isMobile ? 16 : 18,
                                height: isMobile ? 16 : 18,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => const Icon(Icons.shield_outlined, size: 14, color: Colors.white30),
                              )
                            else
                              const Icon(Icons.shield_outlined, size: 14, color: Colors.white30),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                match.homeTeam,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 11.5 : 12.5,
                                  fontWeight: match.isMuFavorite || match.isVietnam ? FontWeight.bold : FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Away Team
                        Row(
                          children: [
                            if (match.awayLogo.isNotEmpty)
                              CachedNetworkImage(
                                imageUrl: match.awayLogo,
                                width: isMobile ? 16 : 18,
                                height: isMobile ? 16 : 18,
                                fit: BoxFit.contain,
                                errorWidget: (_, __, ___) => const Icon(Icons.shield_outlined, size: 14, color: Colors.white30),
                              )
                            else
                              const Icon(Icons.shield_outlined, size: 14, color: Colors.white30),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                match.awayTeam,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 11.5 : 12.5,
                                  fontWeight: match.isMuFavorite || match.isVietnam ? FontWeight.bold : FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Row 3: Kickoff Time & Priority Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Kickoff time or Score
                      Text(
                        match.score.isNotEmpty
                            ? match.score
                            : (match.isOngoingNow ? match.liveMinuteLabel : match.time),
                        style: TextStyle(
                          color: match.isOngoingNow ? const Color(0xFF38BDF8) : Colors.white60,
                          fontSize: isMobile ? 9.5 : 10.5,
                          fontWeight: match.isOngoingNow ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),

                      // Priority Badge (MU / VN / EPL / C1 / Hot)
                      if (badgeLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: badgeColor, width: 0.7),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: badgeColor,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
