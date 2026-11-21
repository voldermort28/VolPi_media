import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/anime_model.dart';
import '../models/iptv_channel_model.dart';
import '../models/match_model.dart';
import '../player/video_player_screen.dart';
import '../widgets/loading_dialog_helper.dart';
import '../widgets/tv_focusable_card.dart';
import 'anime_detail_screen.dart';

/// Màn hình Tìm Kiếm Toàn Cục (Global Search) hỗ trợ cả Android TV D-Pad và Mobile (iOS/Android Phone).
/// Tìm đồng thời trên Bóng Đá, Anime/Phim và Kênh IPTV + lưu lịch sử tìm gần đây.
class GlobalSearchScreen extends StatefulWidget {
  final ApiService apiService;

  const GlobalSearchScreen({super.key, required this.apiService});

  static final List<String> _recentQueries = [];

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  bool _isSearching = false;
  List<MatchModel> _matchResults = [];
  List<AnimeModel> _animeResults = [];
  List<IptvChannelModel> _iptvResults = [];

  // Cache nhẹ cho phiên tìm kiếm để gõ phím phản hồi tức thì
  List<MatchModel>? _cachedMatches;
  List<IptvChannelModel>? _cachedChannels;
  List<AnimeModel>? _cachedAnimes;
  int _searchGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
    _preloadQuickData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _preloadQuickData() async {
    try {
      final results = await Future.wait([
        widget.apiService.getLiveMatches(source: 'xoilac').catchError((_) => <MatchModel>[]),
        widget.apiService.getIptvChannels().catchError((_) => <IptvChannelModel>[]),
        widget.apiService.getAnimeCatalog('yumei-anime').catchError((_) => <AnimeModel>[]),
        widget.apiService.getAnimeCatalog('yumei-pokemon').catchError((_) => <AnimeModel>[]),
        widget.apiService.getAnimeCatalog('yumei-sentai').catchError((_) => <AnimeModel>[]),
        widget.apiService.getAnimeCatalog('yumei-power-rangers').catchError((_) => <AnimeModel>[]),
        widget.apiService.getAnimeCatalog('yumei-movies').catchError((_) => <AnimeModel>[]),
      ]);
      if (!mounted) return;
      _cachedMatches = results[0] as List<MatchModel>;
      _cachedChannels = results[1] as List<IptvChannelModel>;
      final seen = <String>{};
      final allAnimes = <AnimeModel>[];
      for (int i = 2; i <= 6; i++) {
        for (final a in (results[i] as List<AnimeModel>)) {
          if (seen.add(a.id)) allAnimes.add(a);
        }
      }
      _cachedAnimes = allAnimes;
    } catch (_) {}
  }

  void _onQueryChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      _executeSearch(val);
    });
  }

  Future<void> _executeSearch(String rawQuery) async {
    final q = rawQuery.trim();
    final gen = ++_searchGen;
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _query = '';
          _isSearching = false;
          _matchResults = [];
          _animeResults = [];
          _iptvResults = [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _query = q;
        _isSearching = true;
      });
    }

    // Lưu lịch sử tìm gần đây (tối đa 6 từ khóa)
    GlobalSearchScreen._recentQueries.removeWhere((e) => e.toLowerCase() == q.toLowerCase());
    GlobalSearchScreen._recentQueries.insert(0, q);
    if (GlobalSearchScreen._recentQueries.length > 6) {
      GlobalSearchScreen._recentQueries.removeLast();
    }

    final lower = q.toLowerCase();

    // 1. Lọc Bóng đá & IPTV tức thì từ cache (nếu chưa có thì tải)
    List<MatchModel> matches = _cachedMatches ?? [];
    if (matches.isEmpty) {
      try {
        matches = await widget.apiService.getLiveMatches(source: 'xoilac');
        _cachedMatches = matches;
      } catch (_) {}
    }
    final filteredMatches = matches.where((m) {
      return m.homeTeam.toLowerCase().contains(lower) ||
          m.awayTeam.toLowerCase().contains(lower) ||
          m.league.toLowerCase().contains(lower);
    }).take(12).toList();

    List<IptvChannelModel> channels = _cachedChannels ?? [];
    if (channels.isEmpty) {
      try {
        channels = await widget.apiService.getIptvChannels();
        _cachedChannels = channels;
      } catch (_) {}
    }
    final filteredChannels = channels.where((c) {
      return c.name.toLowerCase().contains(lower) ||
          c.cleanTitle.toLowerCase().contains(lower) ||
          c.group.toLowerCase().contains(lower);
    }).take(12).toList();

    // 2. Lọc Anime & Phim từ toàn bộ 5 danh mục Yumei
    List<AnimeModel> animes = _cachedAnimes ?? [];
    if (animes.isEmpty) {
      try {
        animes = await widget.apiService.getAnimeCatalog('yumei-anime');
        _cachedAnimes = animes;
      } catch (_) {}
    }
    final filteredAnimes = animes.where((a) {
      return a.name.toLowerCase().contains(lower) ||
          a.description.toLowerCase().contains(lower);
    }).take(20).toList();

    if (!mounted || gen != _searchGen) return;
    setState(() {
      _matchResults = filteredMatches;
      _iptvResults = filteredChannels;
      _animeResults = filteredAnimes;
      _isSearching = false;
    });
  }

  Future<void> _openMatch(MatchModel match) async {
    final streams = await LoadingDialogHelper.runWithLoading(
      context,
      () => widget.apiService.getMatchStreams(match.id, source: 'xoilac'),
    );
    if (!mounted || streams == null) return;
    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có luồng phát sóng cho trận này.'), backgroundColor: Colors.amber),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: streams.first.url,
          title: '${match.homeTeam} vs ${match.awayTeam}',
          subtitle: '${streams.first.title} • ${match.league}',
          headers: streams.first.headers,
          availableChannels: streams,
          isLive: true,
        ),
      ),
    );
  }

  void _openChannel(IptvChannelModel channel) {
    final primary = channel.toStreamChannel(baseUrl: widget.apiService.baseUrl);
    final streams = _iptvResults
        .map((c) => c.toStreamChannel(baseUrl: widget.apiService.baseUrl))
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: primary.url,
          title: channel.name,
          subtitle: channel.group,
          headers: primary.headers,
          availableChannels: streams,
          isLive: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyResult = _matchResults.isNotEmpty || _animeResults.isNotEmpty || _iptvResults.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          children: [
            // Search Top Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                border: Border(bottom: BorderSide(color: Color(0xFF262626))),
              ),
              child: Row(
                children: [
                  TvFocusableCard(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFF1F1F1F),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: Color(0xFFE50914), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _searchFocusNode,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                hintText: 'Tìm đội bóng, Anime, Phim, Kênh VTV/K+...',
                                hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              onChanged: _onQueryChanged,
                              onSubmitted: _executeSearch,
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            TvFocusableCard(
                              onTap: () {
                                _controller.clear();
                                _executeSearch('');
                                _searchFocusNode.requestFocus();
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
                  : _query.isEmpty
                      ? _buildEmptyPrompt()
                      : !hasAnyResult
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.search_off_rounded, color: Colors.white24, size: 52),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Không tìm thấy kết quả cho "$_query"',
                                    style: const TextStyle(color: Colors.white60, fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                if (_matchResults.isNotEmpty) ...[
                                  _buildHeader('⚽ TRẬN BÓNG ĐÁ (${_matchResults.length})'),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: _matchResults.map((m) {
                                      return SizedBox(
                                        width: 240,
                                        child: TvFocusableCard(
                                          onTap: () => _openMatch(m),
                                          borderRadius: BorderRadius.circular(8),
                                          focusBorderColor: Colors.white,
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF181818),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.white10),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${m.league} • ${m.isLive ? "LIVE" : m.time}',
                                                  style: TextStyle(
                                                    color: m.isLive ? const Color(0xFFE50914) : const Color(0xFF38BDF8),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '${m.homeTeam} vs ${m.awayTeam}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 22),
                                ],
                                if (_iptvResults.isNotEmpty) ...[
                                  _buildHeader('📺 KÊNH TRUYỀN HÌNH IPTV (${_iptvResults.length})'),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: _iptvResults.map((ch) {
                                      return TvFocusableCard(
                                        onTap: () => _openChannel(ch),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF181818),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.white10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.live_tv_rounded, color: Color(0xFF38BDF8), size: 16),
                                              const SizedBox(width: 8),
                                              Text(
                                                ch.name,
                                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 22),
                                ],
                                if (_animeResults.isNotEmpty) ...[
                                  _buildHeader('🍿 ANIME & PHIM (${_animeResults.length})'),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 14,
                                    children: _animeResults.map((anime) {
                                      return SizedBox(
                                        width: 132,
                                        height: 210,
                                        child: TvFocusableCard(
                                          onTap: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => AnimeDetailScreen(
                                                  anime: anime,
                                                  apiService: widget.apiService,
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          focusBorderColor: Colors.white,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF181818),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                                    child: anime.poster.isNotEmpty
                                                        ? CachedNetworkImage(
                                                            imageUrl: anime.poster,
                                                            fit: BoxFit.cover,
                                                            width: double.infinity,
                                                            memCacheWidth: 160,
                                                            memCacheHeight: 240,
                                                            errorWidget: (_, __, ___) => Container(color: const Color(0xFF262626)),
                                                          )
                                                        : Container(color: const Color(0xFF262626)),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.all(7),
                                                  child: Text(
                                                    anime.name,
                                                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4),
      ),
    );
  }

  Widget _buildEmptyPrompt() {
    final quickTags = GlobalSearchScreen._recentQueries.isNotEmpty
        ? GlobalSearchScreen._recentQueries
        : ['VTV3', 'Man Utd', 'Pokemon', 'Kamen Rider', 'VTV1', 'One Piece'];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GlobalSearchScreen._recentQueries.isNotEmpty ? 'TÌM KIẾM GẦN ĐÂY' : 'GỢI Ý TÌM NHANH',
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: quickTags.map((tag) {
              return TvFocusableCard(
                onTap: () {
                  _controller.text = tag;
                  _executeSearch(tag);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, color: Colors.white54, size: 15),
                      const SizedBox(width: 6),
                      Text(tag, style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
