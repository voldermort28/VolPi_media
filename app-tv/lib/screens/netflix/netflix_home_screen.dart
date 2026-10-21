import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/api_service.dart';
import '../../models/match_model.dart';
import '../../models/watch_history_model.dart';
import '../../player/video_player_screen.dart';
import '../../services/watch_history_service.dart';
import '../../widgets/resume_playback_dialog.dart';
import '../../widgets/tv_focusable_card.dart';
import '../../widgets/netflix/netflix_scrollable_row.dart';

class NetflixHomeScreen extends StatefulWidget {
  final ApiService apiService;
  final ValueChanged<int>? onNavigateTab;

  const NetflixHomeScreen({
    super.key,
    required this.apiService,
    this.onNavigateTab,
  });

  @override
  NetflixHomeScreenState createState() => NetflixHomeScreenState();
}

class NetflixHomeScreenState extends State<NetflixHomeScreen> {
  Future<void> refresh() => _loadData(forceRefresh: true);

  List<MatchModel> _matches = [];
  List<MatchModel> _majorMatches = [];
  List<MatchModel> _liveMatches = [];
  List<MatchModel> _vietnamMatches = [];
  List<WatchHistoryItem> _continueWatching = [];
  bool _isLoading = true;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _billboardPlayFocusNode = FocusNode();
  final PageController _bannerPageController = PageController();
  Timer? _bannerTimer;
  int _currentBannerIndex = 0;
  bool _isBannerInteracting = false;

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.changeNotifier.addListener(_onHistoryChanged);
    _loadData();
  }

  @override
  void dispose() {
    WatchHistoryService.instance.changeNotifier.removeListener(_onHistoryChanged);
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    _scrollController.dispose();
    _billboardPlayFocusNode.dispose();
    super.dispose();
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    final featuredMatches = _majorMatches.isNotEmpty
        ? _majorMatches.take(5).toList()
        : (_matches.isNotEmpty ? _matches.take(3).toList() : <MatchModel>[]);
    if (featuredMatches.length <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (!mounted || _isBannerInteracting) return;
      if (_bannerPageController.hasClients) {
        final nextIndex = (_currentBannerIndex + 1) % featuredMatches.length;
        _bannerPageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  void _scrollToTopOnBillboardFocus() {
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onHistoryChanged() {
    if (mounted) {
      setState(() {
        _continueWatching = WatchHistoryService.instance.getContinueWatching(excludeCategory: 'secret');
      });
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await widget.apiService.getLiveMatches(forceRefresh: forceRefresh, source: 'xoilac');
      if (!mounted) return;

      final nonEsports = results.where((m) => !m.isEsports).toList();

      // 1. Vietnam Football matches (V-League 1 & 2, Cúp Quốc Gia, ĐTQG, C1/C2 Châu Á...)
      final vnMatches = nonEsports
          .where((m) => m.isVietnam && !m.isFinishedMatch)
          .toList();

      vnMatches.sort((a, b) {
        if (a.isOngoingNow != b.isOngoingNow) {
          return a.isOngoingNow ? -1 : 1;
        }
        return a.matchTimestamp.compareTo(b.matchTimestamp);
      });

      // 2. Score-based ranking for Major Matches (Tâm điểm & Hero Banner)
      int getMatchScore(MatchModel m) {
        int score = 0;
        // Tier 1: Đội Tuyển Việt Nam & V-League (Ưu tiên số 1 tuyệt đối cho khán giả Việt Nam)
        if (m.isVietnam) score += 10000;
        // Tier 2: Manchester United (CLB Yêu thích số 1 của User)
        if (m.isMuFavorite) score += 8000;
        // Tier 3: Đại chiến CLB hàng đầu thế giới (Real Madrid, Barca, Man City, Arsenal, Liverpool, Bayern, v.v.)
        if (m.isFavorite) score += 6000;
        // Tier 4: Ngoại Hạng Anh & Cúp C1 Châu Âu (UEFA Champions League chuẩn)
        if (m.isPremierLeagueOrC1) score += 4000;
        // Tier 5: Trận Hot / Famous từ hệ thống
        if (m.isHot) score += 2000;
        if (m.isFamous) score += 1000;

        // Trận đang diễn ra trực tiếp được ưu tiên hơn trận chưa đá
        if (m.isOngoingNow) score += 500;

        return score;
      }

      final major = nonEsports
          .where((m) =>
              !m.isFinishedMatch &&
              (m.isFamous || m.isVietnam || m.isFavorite || m.isHot || m.isPremierLeagueOrC1))
          .toList();

      major.sort((a, b) {
        final scoreA = getMatchScore(a);
        final scoreB = getMatchScore(b);
        if (scoreA != scoreB) {
          return scoreB.compareTo(scoreA); // High score first
        }
        return a.matchTimestamp.compareTo(b.matchTimestamp);
      });

      // 3. Live now matches
      final live = nonEsports.where((m) => m.isOngoingNow && !m.isFinishedMatch).toList();

      setState(() {
        _matches = nonEsports;
        _vietnamMatches = vnMatches;
        _majorMatches = major;
        _liveMatches = live;
        _continueWatching = WatchHistoryService.instance.getContinueWatching(excludeCategory: 'secret');
        _isLoading = false;
      });

      _startBannerTimer();

      // Auto-focus billboard play button
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _majorMatches.isNotEmpty) {
          _billboardPlayFocusNode.requestFocus();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể tải dữ liệu: $e';
        });
      }
    }
  }

  void _onMatchSelected(MatchModel match) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );

    final streams = await widget.apiService.getMatchStreams(match.id, source: 'xoilac');
    if (!mounted) return;
    Navigator.of(context).pop();

    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có luồng phát sóng cho trận này hoặc trận chưa diễn ra.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    // Auto-play first stream (Netflix zero-friction standard)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: streams[0].url,
          title: '${match.homeTeam} vs ${match.awayTeam}',
          subtitle: '${streams[0].title} • ${match.league}',
          headers: streams[0].headers,
          availableChannels: streams,
          isLive: true,
        ),
      ),
    );
  }

  void _onContinueWatchingTap(WatchHistoryItem item) async {
    if (item.streamUrl.isNotEmpty) {
      final choice = await ResumePlaybackDialog.show(context, item);
      if (choice == null || !mounted) return;

      final startPos = choice ? Duration(milliseconds: item.positionMs) : Duration.zero;
      if (!choice) {
        WatchHistoryService.instance.clearProgress(item.id);
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            streamUrl: item.streamUrl,
            title: item.title,
            subtitle: 'Tập ${item.episode}',
            mediaId: item.mediaId,
            mediaPoster: item.poster,
            episode: item.episode,
            season: item.season,
            initialPosition: startPos,
            isLive: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFE50914)),
            SizedBox(height: 14),
            Text(
              'Đang tải Netflix Cinema...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 48),
            const SizedBox(height: 12),
            Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 16),
            TvFocusableCard(
              onTap: _loadData,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFFE50914),
                child: const Text('Thử lại', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }

    final featuredMatches = _majorMatches.isNotEmpty
        ? _majorMatches.take(5).toList()
        : (_matches.isNotEmpty ? _matches.take(3).toList() : <MatchModel>[]);

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. BILLBOARD HERO BANNER (Top Matches Carousel)
          if (featuredMatches.isNotEmpty) _buildBillboardCarousel(featuredMatches),

          const SizedBox(height: 16),

          // 2. CONTINUE WATCHING (🍿 TIẾP TỤC XEM)
          if (_continueWatching.isNotEmpty) ...[
            _buildSectionTitle('🍿 TIẾP TỤC XEM CHO BẠN'),
            _buildContinueWatchingRow(),
            const SizedBox(height: 20),
          ],

          // 3. LIVE NOW MATCHES (🔴 ĐANG THI ĐẤU TRỰC TIẾP)
          if (_liveMatches.isNotEmpty) ...[
            _buildSectionTitle('🔴 ĐANG THI ĐẤU TRỰC TIẾP', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_liveMatches),
            const SizedBox(height: 20),
          ],

          // 3.5. VIETNAM FOOTBALL (🇻🇳 BÓNG ĐÁ VIỆT NAM & V-LEAGUE)
          if (_vietnamMatches.isNotEmpty) ...[
            _buildSectionTitle('🇻🇳 BÓNG ĐÁ VIỆT NAM & V-LEAGUE', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_vietnamMatches),
            const SizedBox(height: 20),
          ] else ...[
            _buildSectionTitle('🇻🇳 BÓNG ĐÁ VIỆT NAM & V-LEAGUE', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildVietnamEmptyBanner(),
            const SizedBox(height: 20),
          ],

          // 4. SPOTLIGHT MATCHES (⭐ TRẬN CẦU TÂM ĐIỂM & GIẢI ĐẤU HÀNG ĐẦU)
          if (_majorMatches.isNotEmpty) ...[
            _buildSectionTitle('⭐ TRẬN CẦU TÂM ĐIỂM & GIẢI HÀNG ĐẦU', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_majorMatches),
            const SizedBox(height: 20),
          ],

          // 5. ALL MATCHES (⚽ CÁC TRẬN ĐẤU KHÁC)
          if (_matches.isNotEmpty) ...[
            _buildSectionTitle('⚽ CÁC TRẬN ĐẤU KHÁC HÔM NAY', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_matches.skip(3).take(10).toList()),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // BILLBOARD CAROUSEL (Top Matches Auto-Slide)
  // =========================================================================
  Widget _buildBillboardCarousel(List<MatchModel> featuredMatches) {
    if (featuredMatches.isEmpty) return const SizedBox.shrink();
    if (featuredMatches.length == 1) return _buildBillboard(featuredMatches.first);

    return MouseRegion(
      onEnter: (_) => setState(() => _isBannerInteracting = true),
      onExit: (_) => setState(() => _isBannerInteracting = false),
      child: SizedBox(
        height: 300,
        child: Stack(
          children: [
            PageView.builder(
              controller: _bannerPageController,
              itemCount: featuredMatches.length,
              onPageChanged: (idx) {
                setState(() {
                  _currentBannerIndex = idx;
                });
              },
              itemBuilder: (context, idx) {
                return _buildBillboard(featuredMatches[idx]);
              },
            ),

            // Dots Indicator (Góc dưới bên phải)
            Positioned(
              bottom: 24,
              right: 32,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(featuredMatches.length, (idx) {
                  final bool isSelected = idx == _currentBannerIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isSelected ? 18 : 6,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFE50914) : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // VIETNAM EMPTY STATE BANNER (When no VN matches scheduled)
  // =========================================================================
  Widget _buildVietnamEmptyBanner() {
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 14 : 20, vertical: isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3), width: 1.0),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF991B1B).withOpacity(0.18),
            const Color(0xFF141414),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Text('🇻🇳', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Lịch Thi Đấu Bóng Đá Việt Nam',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Hôm nay chưa có trận diễn ra. Các trận đấu V.League 1 & 2, Cúp Quốc Gia, C1/C2 Châu Á (Nam Định, CAHN...) và ĐT Việt Nam (AFF Cup, Vòng loại World Cup) sẽ tự động cập nhật khi có lịch phát sóng.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: isMobile ? 10.5 : 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TvFocusableCard(
            onTap: () => widget.onNavigateTab?.call(1),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Xem tất cả',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // BILLBOARD COMPONENT
  // =========================================================================
  Widget _buildBillboard(MatchModel match) {
    return Container(
      height: 300,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        gradient: LinearGradient(
          colors: [Color(0xFF1E1428), Color(0xFF0A0F1D), Color(0xFF0F0F0F)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dark Vignette Gradient Left-to-Right
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F0F0F), Color(0xCC0F0F0F), Colors.transparent],
                stops: [0.0, 0.55, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          // Dark Vignette Gradient Bottom-to-Top
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F0F0F), Colors.transparent],
                stops: [0.0, 0.6],
                begin: Alignment.bottomCenter,
                end: Alignment.center,
              ),
            ),
          ),

          // Billboard Content
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Badges
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: match.isVietnam ? const Color(0xFFDC2626) : const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        match.isVietnam
                            ? '🇻🇳 BÓNG ĐÁ VIỆT NAM'
                            : (match.isMuFavorite
                                ? '⭐ MANCHESTER UNITED'
                                : (match.favoriteBadgeText.isNotEmpty
                                    ? '⭐ ${match.favoriteBadgeText}'
                                    : 'TOP 1 TÂM ĐIỂM')),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      match.league.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      match.isOngoingNow ? '• LIVE ${match.liveMinuteLabel}' : '• ${match.time}',
                      style: TextStyle(
                        color: match.isOngoingNow ? const Color(0xFFF43F5E) : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Match Title
                Text(
                  '${match.homeTeam}  vs  ${match.awayTeam}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 6),

                // Subtitle
                Text(
                  match.isOngoingNow
                      ? 'Đang thi đấu trực tiếp • Bình luận tiếng Việt Full HD 60fps'
                      : 'Trực tiếp chất lượng cao • Bình luận tiếng Việt độc quyền',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),

                const SizedBox(height: 16),

                // Actions: Netflix White "PHÁT NGAY" button + Info
                Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _scrollToTopOnBillboardFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Row(
                    children: [
                      TvFocusableCard(
                        focusNode: _billboardPlayFocusNode,
                        onFocusChange: (hasFocus) {
                          if (hasFocus) _scrollToTopOnBillboardFocus();
                        },
                        onTap: () => _onMatchSelected(match),
                        borderRadius: BorderRadius.circular(6),
                        scale: 1.05,
                        focusBorderColor: Colors.white,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                              SizedBox(width: 6),
                              Text(
                                'PHÁT NGAY',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      TvFocusableCard(
                        onFocusChange: (hasFocus) {
                          if (hasFocus) _scrollToTopOnBillboardFocus();
                        },
                        onTap: () => _onMatchSelected(match),
                        borderRadius: BorderRadius.circular(6),
                        scale: 1.05,
                        focusBorderColor: Colors.white,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF333333).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'CHỌN LUỒNG & BLV',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
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
        ],
      ),
    );
  }

  // =========================================================================
  // SECTION TITLE
  // =========================================================================
  Widget _buildSectionTitle(String title, {VoidCallback? onSeeAll}) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 24,
        vertical: isMobile ? 4 : 6,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: isMobile ? 13 : 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onSeeAll != null) ...[
            const SizedBox(width: 8),
            TvFocusableCard(
              onTap: onSeeAll,
              borderRadius: BorderRadius.circular(4),
              scale: 1.02,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      'Xem tất cả',
                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Color(0xFF38BDF8), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // CONTINUE WATCHING HORIZONTAL ROW (16:9 ratio + Netflix Red Progress Bar)
  // =========================================================================
  Widget _buildContinueWatchingRow() {
    return NetflixScrollableRow(
      height: 140,
      itemCount: _continueWatching.length,
      itemBuilder: (context, idx) {
          final item = _continueWatching[idx];
          return RepaintBoundary(
            child: TvFocusableCard(
              onTap: () => _onContinueWatchingTap(item),
              borderRadius: BorderRadius.circular(6),
              scale: 1.05,
              focusBorderColor: Colors.white,
              child: Container(
                width: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail 16:9
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (item.poster.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: item.poster,
                              fit: BoxFit.cover,
                              memCacheWidth: 200,
                              memCacheHeight: 120,
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF262626),
                                child: const Icon(Icons.movie_rounded, color: Colors.white30),
                              ),
                            )
                          else
                            Container(color: const Color(0xFF262626)),

                          // Episode Badge
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'TẬP ${item.episode}',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),

                          // Center Play Icon
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                            ),
                          ),

                          // Netflix Red Progress Bar
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 3.5,
                            child: Container(
                              color: const Color(0xFF333333),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: item.progressPercent.clamp(0.0, 1.0),
                                child: Container(color: const Color(0xFFE50914)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Info
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.formattedPosition} / ${item.formattedDuration}',
                            style: const TextStyle(color: Color(0xFFE50914), fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
    );
  }

  // =========================================================================
  // MATCHES HORIZONTAL ROW (Netflix Card Style)
  // =========================================================================
  Widget _buildMatchesRow(List<MatchModel> matches) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;
    final double cardWidth = isMobile ? 195 : 250;
    final double rowHeight = isMobile ? 112 : 155;

    return NetflixScrollableRow(
      height: rowHeight,
      itemCount: matches.length,
      itemBuilder: (context, idx) {
        final match = matches[idx];
        return RepaintBoundary(
          child: TvFocusableCard(
            onTap: () => _onMatchSelected(match),
            borderRadius: BorderRadius.circular(6),
            scale: 1.05,
            focusBorderColor: Colors.white,
            child: Container(
              width: cardWidth,
              padding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                  : const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color: match.isVietnam
                        ? const Color(0xFFEAB308)
                        : (match.isMuFavorite
                            ? const Color(0xFFDC2626)
                            : (match.isOngoingNow
                                ? const Color(0xFFE50914)
                                : (match.isPremierLeagueOrC1 ? const Color(0xFF38BDF8) : Colors.transparent))),
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
                  // Header: League & Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          match.league,
                          style: TextStyle(
                            color: const Color(0xFFA3A3A3),
                            fontSize: isMobile ? 10 : 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 5 : 6,
                          vertical: isMobile ? 1.5 : 2,
                        ),
                        decoration: BoxDecoration(
                          color: match.isOngoingNow
                              ? const Color(0xFFE50914).withOpacity(0.2)
                              : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          match.isOngoingNow ? 'LIVE ${match.liveMinuteLabel}' : match.time,
                          style: TextStyle(
                            color: match.isOngoingNow ? const Color(0xFFE50914) : const Color(0xFF38BDF8),
                            fontSize: isMobile ? 9.5 : 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Teams
                  Column(
                    children: [
                      _buildTeamRow(match.homeTeam, match.homeLogo, isMobile: isMobile),
                      SizedBox(height: isMobile ? 3 : 6),
                      _buildTeamRow(match.awayTeam, match.awayLogo, isMobile: isMobile),
                    ],
                  ),

                  // Footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          match.isOngoingNow ? '🔴 Đang trực tiếp' : 'Full HD • BLV Tiếng Việt',
                          style: TextStyle(
                            color: match.isOngoingNow ? const Color(0xFFE50914) : const Color(0xFF737373),
                            fontSize: isMobile ? 9.5 : 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: isMobile ? 14 : 16,
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

  Widget _buildTeamRow(String teamName, String logoUrl, {bool isMobile = false}) {
    final double logoSize = isMobile ? 17 : 20;
    return Row(
      children: [
        if (logoUrl.isNotEmpty)
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              width: logoSize,
              height: logoSize,
              fit: BoxFit.cover,
              memCacheWidth: 40,
              memCacheHeight: 40,
              errorWidget: (_, __, ___) => Container(
                width: logoSize,
                height: logoSize,
                color: const Color(0xFF262626),
                child: Icon(Icons.shield_rounded, size: isMobile ? 10 : 12, color: Colors.white38),
              ),
            ),
          )
        else
          Container(
            width: logoSize,
            height: logoSize,
            decoration: const BoxDecoration(color: Color(0xFF262626), shape: BoxShape.circle),
            child: Icon(Icons.shield_rounded, size: isMobile ? 10 : 12, color: Colors.white38),
          ),
        SizedBox(width: isMobile ? 6 : 8),
        Expanded(
          child: Text(
            teamName,
            style: TextStyle(
              color: Colors.white,
              fontSize: isMobile ? 11.5 : 12,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
