import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/api_service.dart';
import '../../models/anime_model.dart';
import '../../models/favorite_item_model.dart';
import '../../models/match_model.dart';
import '../../models/watch_history_model.dart';
import '../../player/video_player_screen.dart';
import '../../services/favorites_service.dart';
import '../../services/sync_service.dart';
import '../../services/watch_history_service.dart';
import '../../widgets/resume_playback_dialog.dart';
import '../../widgets/tv_focusable_card.dart';
import '../../widgets/netflix/netflix_scrollable_row.dart';
import '../anime_detail_screen.dart';

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
  List<FavoriteItem> _favorites = [];
  bool _isLoading = true;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _firstHomeCardFocusNode = FocusNode();
  FocusNode get firstCardFocusNode => _firstHomeCardFocusNode;
  FocusNode get billboardPlayFocusNode => _firstHomeCardFocusNode;

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.changeNotifier.addListener(_onHistoryChanged);
    FavoritesService.instance.changeNotifier.addListener(_onFavoritesChanged);
    _loadData();
  }

  @override
  void dispose() {
    WatchHistoryService.instance.changeNotifier.removeListener(_onHistoryChanged);
    FavoritesService.instance.changeNotifier.removeListener(_onFavoritesChanged);
    _scrollController.dispose();
    _firstHomeCardFocusNode.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) {
      setState(() {
        _continueWatching = WatchHistoryService.instance.getContinueWatching(excludeCategory: 'secret');
      });
    }
  }

  void _onFavoritesChanged() {
    if (mounted) {
      setState(() {
        _favorites = FavoritesService.instance.getFavorites().where((f) => f.category != 'secret').toList();
      });
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (forceRefresh) {
      SyncService.syncFull(widget.apiService.baseUrl);
    }

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
        _favorites = FavoritesService.instance.getFavorites().where((f) => f.category != 'secret').toList();
        _isLoading = false;
      });

      // Tự động focus thẻ nội dung đầu tiên trên Android TV khi tải xong dữ liệu
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _firstHomeCardFocusNode.canRequestFocus) {
          _firstHomeCardFocusNode.requestFocus();
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

  void _onContinueWatchingTap(WatchHistoryItem item) {
    final idx = _continueWatching.indexWhere((h) => h.id == item.id);
    if (idx != -1) {
      _playContinueWatchingAtIndex(idx);
    }
  }

  String _cleanAnimeSlug(String rawId) {
    String id = rawId.trim();
    id = id.replaceAll(RegExp(r'^anime:'), '');
    id = id.replaceAll(RegExp(r':ep:\d+.*$'), '');
    id = id.replaceAll(RegExp(r':\d+:\d+$'), '');
    return id;
  }

  int _extractEpisodeNumber(WatchHistoryItem item) {
    if (item.episode > 0) return item.episode;
    final match = RegExp(r':ep:(\d+)').firstMatch(item.id) ?? RegExp(r':\d+:(\d+)$').firstMatch(item.id);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 1;
    }
    return 1;
  }

  void _playContinueWatchingAtIndex(int index, {BuildContext? replaceContext}) async {
    if (index < 0 || index >= _continueWatching.length) return;
    final item = _continueWatching[index];
    final targetContext = replaceContext ?? context;

    Duration startPos = Duration(milliseconds: item.positionMs);
    if (replaceContext == null) {
      final choice = await ResumePlaybackDialog.show(context, item);
      if (choice == null || !mounted) return;
      startPos = choice ? Duration(milliseconds: item.positionMs) : Duration.zero;
      if (!choice) {
        WatchHistoryService.instance.clearProgress(item.id);
      }
    }

    final cleanId = _cleanAnimeSlug(item.mediaId.isNotEmpty ? item.mediaId : item.id);
    final epNum = _extractEpisodeNumber(item);
    final isAnimeSeries = (item.category == 'anime' || item.id.startsWith('anime:') || item.id.startsWith('yumei:')) && cleanId.isNotEmpty;

    final playerRoute = MaterialPageRoute(
      builder: (playerCtx) => VideoPlayerScreen(
        streamUrl: item.streamUrl,
        title: item.title,
        subtitle: epNum > 0 ? 'Tập $epNum' : '',
        mediaId: item.mediaId.isNotEmpty ? item.mediaId : item.id,
        mediaPoster: item.poster,
        episode: epNum,
        season: item.season,
        availableChannels: [
          StreamChannel(
            name: 'Server 1',
            title: epNum > 0 ? 'Tập $epNum' : item.title,
            url: item.streamUrl,
            headers: const {},
          ),
        ],
        initialPosition: startPos,
        isLive: false,
        onNext: isAnimeSeries
            ? () => _loadAndPlayEpisode(
                  animeId: cleanId,
                  animeTitle: item.title,
                  poster: item.poster,
                  season: item.season > 0 ? item.season : 1,
                  episode: epNum + 1,
                  continueIndex: index,
                  replaceContext: playerCtx,
                )
            : null,
        onPrevious: isAnimeSeries && epNum > 1
            ? () => _loadAndPlayEpisode(
                  animeId: cleanId,
                  animeTitle: item.title,
                  poster: item.poster,
                  season: item.season > 0 ? item.season : 1,
                  episode: epNum - 1,
                  continueIndex: index,
                  replaceContext: playerCtx,
                )
            : null,
      ),
    );

    if (replaceContext != null) {
      Navigator.of(replaceContext).pushReplacement(playerRoute);
    } else {
      Navigator.of(context).push(playerRoute);
    }
  }

  void _loadAndPlayEpisode({
    required String animeId,
    required String animeTitle,
    required String poster,
    required int season,
    required int episode,
    required int continueIndex,
    BuildContext? replaceContext,
  }) async {
    final targetContext = replaceContext ?? context;

    showDialog(
      context: targetContext,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFE50914)),
      ),
    );

    final streams = await widget.apiService.getAnimeEpisodeStreams(
      animeId,
      season,
      episode,
    );

    if (!mounted) return;
    Navigator.of(targetContext).pop();

    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không tìm thấy tập $episode hoặc đã hết các tập của $animeTitle!'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final playStream = streams.first;
    final historyId = 'anime:$animeId:ep:$episode';

    final playerRoute = MaterialPageRoute(
      builder: (playerCtx) => VideoPlayerScreen(
        streamUrl: playStream.url,
        title: animeTitle,
        subtitle: 'Tập $episode',
        headers: playStream.headers,
        availableChannels: streams,
        mediaId: historyId,
        mediaCategory: 'anime',
        mediaPoster: poster,
        episode: episode,
        season: season,
        isLive: false,
        onNext: () {
          _loadAndPlayEpisode(
            animeId: animeId,
            animeTitle: animeTitle,
            poster: poster,
            season: season,
            episode: episode + 1,
            continueIndex: continueIndex,
            replaceContext: playerCtx,
          );
        },
        onPrevious: episode > 1
            ? () {
                _loadAndPlayEpisode(
                  animeId: animeId,
                  animeTitle: animeTitle,
                  poster: poster,
                  season: season,
                  episode: episode - 1,
                  continueIndex: continueIndex,
                  replaceContext: playerCtx,
                );
              }
            : null,
      ),
    );

    if (replaceContext != null) {
      Navigator.of(replaceContext).pushReplacement(playerRoute);
    } else {
      Navigator.of(context).push(playerRoute);
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
              'Loading...',
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

    // Xác định mục đầu tiên để gán focus node chính (primary entry node cho Android TV)
    final bool hasContinue = _continueWatching.isNotEmpty;
    final bool hasFavorites = _favorites.isNotEmpty;
    final bool hasLive = _liveMatches.isNotEmpty;
    final bool hasVietnam = _vietnamMatches.isNotEmpty;
    final bool hasMajor = _majorMatches.isNotEmpty;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),

          // 1. CONTINUE WATCHING (🍿 TIẾP TỤC XEM)
          if (hasContinue) ...[
            _buildSectionTitle('🍿 TIẾP TỤC XEM CHO BẠN'),
            _buildContinueWatchingRow(isFirstSection: true),
            const SizedBox(height: 20),
          ],

          // 2. FAVORITES (❤️ DANH SÁCH YÊU THÍCH)
          if (hasFavorites) ...[
            _buildSectionTitle('❤️ DANH SÁCH YÊU THÍCH', onSeeAll: () => widget.onNavigateTab?.call(3)),
            _buildFavoritesRow(isFirstSection: !hasContinue),
            const SizedBox(height: 20),
          ],

          // 3. LIVE NOW MATCHES (🔴 ĐANG THI ĐẤU TRỰC TIẾP)
          if (hasLive) ...[
            _buildSectionTitle('🔴 ĐANG THI ĐẤU TRỰC TIẾP', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_liveMatches, isFirstSection: !hasContinue && !hasFavorites),
            const SizedBox(height: 20),
          ],

          // 4. VIETNAM FOOTBALL (🇻🇳 BÓNG ĐÁ VIỆT NAM & V-LEAGUE)
          if (hasVietnam) ...[
            _buildSectionTitle('🇻🇳 BÓNG ĐÁ VIỆT NAM & V-LEAGUE', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_vietnamMatches, isFirstSection: !hasContinue && !hasFavorites && !hasLive),
            const SizedBox(height: 20),
          ] else ...[
            _buildSectionTitle('🇻🇳 BÓNG ĐÁ VIỆT NAM & V-LEAGUE', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildVietnamEmptyBanner(),
            const SizedBox(height: 20),
          ],

          // 5. SPOTLIGHT MATCHES (⭐ TRẬN CẦU TÂM ĐIỂM & GIẢI ĐẤU HÀNG ĐẦU)
          if (hasMajor) ...[
            _buildSectionTitle('⭐ TRẬN CẦU TÂM ĐIỂM & GIẢI HÀNG ĐẦU', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_majorMatches, isFirstSection: !hasContinue && !hasFavorites && !hasLive && !hasVietnam),
            const SizedBox(height: 20),
          ],

          // 6. ALL MATCHES (⚽ CÁC TRẬN ĐẤU KHÁC)
          if (_matches.isNotEmpty) ...[
            _buildSectionTitle('⚽ CÁC TRẬN ĐẤU KHÁC HÔM NAY', onSeeAll: () => widget.onNavigateTab?.call(1)),
            _buildMatchesRow(_matches.skip(3).take(10).toList(), isFirstSection: !hasContinue && !hasFavorites && !hasLive && !hasVietnam && !hasMajor),
            const SizedBox(height: 32),
          ],
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
      padding: EdgeInsets.fromLTRB(
        isMobile ? 14 : 24,
        12,
        isMobile ? 14 : 24,
        8,
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
        ],
      ),
    );
  }

  // =========================================================================
  // CONTINUE WATCHING HORIZONTAL ROW (16:9 ratio + Netflix Red Progress Bar)
  // =========================================================================
  Widget _buildContinueWatchingRow({bool isFirstSection = false}) {
    return NetflixScrollableRow(
      height: 140,
      itemCount: _continueWatching.length,
      itemBuilder: (context, idx) {
          final item = _continueWatching[idx];
          return RepaintBoundary(
            child: TvFocusableCard(
              focusNode: (isFirstSection && idx == 0) ? _firstHomeCardFocusNode : null,
              onTap: () => _playContinueWatchingAtIndex(idx),
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
  // FAVORITES HORIZONTAL ROW (Poster Ratio)
  // =========================================================================
  Widget _buildFavoritesRow({bool isFirstSection = false}) {
    return NetflixScrollableRow(
      height: 180,
      itemCount: _favorites.length,
      itemBuilder: (context, idx) {
        final item = _favorites[idx];
        return RepaintBoundary(
          child: TvFocusableCard(
            focusNode: (isFirstSection && idx == 0) ? _firstHomeCardFocusNode : null,
            onTap: () => _onFavoriteItemTap(item),
            borderRadius: BorderRadius.circular(6),
            scale: 1.05,
            focusBorderColor: Colors.white,
            child: Container(
              width: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.poster.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: item.poster,
                            fit: BoxFit.cover,
                            memCacheWidth: 150,
                            memCacheHeight: 220,
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF262626),
                              child: const Icon(Icons.favorite_rounded, color: Colors.white30),
                            ),
                          )
                        else
                          Container(color: const Color(0xFF262626)),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite, color: Colors.redAccent, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  void _onFavoriteItemTap(FavoriteItem item) {
    final cleanId = _cleanAnimeSlug(item.id);
    final anime = AnimeModel(
      id: cleanId,
      name: item.title,
      poster: item.poster,
      background: item.poster,
      description: '',
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeDetailScreen(
          anime: anime,
          apiService: widget.apiService,
        ),
      ),
    );
  }

  // =========================================================================
  // MATCHES HORIZONTAL ROW (Netflix Card Style)
  // =========================================================================
  Widget _buildMatchesRow(List<MatchModel> matches, {bool isFirstSection = false}) {
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
            focusNode: (isFirstSection && idx == 0) ? _firstHomeCardFocusNode : null,
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
