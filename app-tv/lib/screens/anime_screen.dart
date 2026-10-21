import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/anime_model.dart';
import '../models/favorite_item_model.dart';
import '../models/watch_history_model.dart';
import '../player/video_player_screen.dart';
import '../services/favorites_service.dart';
import '../services/sync_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/movie_action_dialog.dart';
import '../widgets/resume_playback_dialog.dart';
import '../widgets/tv_focusable_card.dart';
import 'anime_detail_screen.dart';

class AnimeScreen extends StatefulWidget {
  final ApiService apiService;

  const AnimeScreen({super.key, required this.apiService});

  @override
  State<AnimeScreen> createState() => AnimeScreenState();
}

class AnimeScreenState extends State<AnimeScreen> {
  final List<Map<String, String>> _categories = [
    {'id': 'yumei-top', 'name': '🌟 Toàn Bộ'},
    {'id': 'favorites', 'name': '❤️ Yêu Thích'},
    {'id': 'yumei-pokemon', 'name': '⚡ Pokemon'},
    {'id': 'yumei-sentai', 'name': '⚔️ Super Sentai'},
    {'id': 'yumei-power-rangers', 'name': '⚡ Power Rangers'},
    {'id': 'yumei-anime', 'name': '🌸 Anime khác'},
    {'id': 'yumei-movies', 'name': '🎬 Phim Lẻ Anime'},
  ];

  int _selectedCategoryIndex = 0;
  List<AnimeModel> _items = [];
  bool _isLoading = true;
  final Map<String, List<AnimeModel>> _catalogCache = {};

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.changeNotifier.addListener(_onServiceUpdate);
    FavoritesService.instance.changeNotifier.addListener(_onServiceUpdate);
    _loadCategory(0);
  }

  @override
  void dispose() {
    WatchHistoryService.instance.changeNotifier.removeListener(_onServiceUpdate);
    FavoritesService.instance.changeNotifier.removeListener(_onServiceUpdate);
    super.dispose();
  }

  Future<void> refresh() async {
    _catalogCache.clear();
    await _loadCategory(_selectedCategoryIndex);
  }

  void _onServiceUpdate() {
    if (!mounted) return;
    if (_categories[_selectedCategoryIndex]['id'] == 'favorites') {
      _loadFavoritesCategory();
    } else {
      setState(() {});
    }
  }

  void _loadFavoritesCategory() {
    final favs = FavoritesService.instance
        .getFavorites()
        .where((f) => f.category != 'secret')
        .toList();

    setState(() {
      _items = favs
          .map<AnimeModel>((f) => AnimeModel(
                id: f.id.startsWith('anime:') ? f.id.substring(6) : f.id,
                name: f.title,
                poster: f.poster,
                background: f.poster,
                description: '',
              ))
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _loadCategory(int index) async {
    final catId = _categories[index]['id']!;

    if (catId == 'favorites') {
      setState(() {
        _selectedCategoryIndex = index;
        _isLoading = true;
      });
      _loadFavoritesCategory();
      return;
    }

    if (_catalogCache.containsKey(catId)) {
      setState(() {
        _selectedCategoryIndex = index;
        _items = _catalogCache[catId]!;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _selectedCategoryIndex = index;
      _isLoading = true;
    });

    try {
      final items = await widget.apiService.getAnimeCatalog(catId);
      _catalogCache[catId] = items;

      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _findCategoryIndexForAnime(AnimeModel anime) {
    final id = anime.id.toLowerCase();
    final name = anime.name.toLowerCase();
    if (id.contains('pokemon') || name.contains('pokemon')) {
      return _categories.indexWhere((c) => c['id'] == 'yumei-pokemon');
    }
    if (id.contains('sentai') || name.contains('sentai')) {
      return _categories.indexWhere((c) => c['id'] == 'yumei-sentai');
    }
    if (id.contains('power-rangers') || id.contains('rangers') || name.contains('power rangers')) {
      return _categories.indexWhere((c) => c['id'] == 'yumei-power-rangers');
    }
    if (id.contains('movies') || name.contains('phim lẻ')) {
      return _categories.indexWhere((c) => c['id'] == 'yumei-movies');
    }
    if (id.contains('anime') || name.contains('anime khác') || name.contains('digimon') || name.contains('yugioh')) {
      return _categories.indexWhere((c) => c['id'] == 'yumei-anime');
    }
    return -1;
  }

  void _onAnimeCardTap(AnimeModel anime) {
    if (_selectedCategoryIndex == 0) {
      final targetIndex = _findCategoryIndexForAnime(anime);
      if (targetIndex != -1) {
        _loadCategory(targetIndex);
        return;
      }
    }
    _openDetail(anime);
  }

  void _openDetail(AnimeModel anime) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeDetailScreen(
          anime: anime,
          apiService: widget.apiService,
        ),
      ),
    );
  }

  void _openDetailWithPlaylist(List<AnimeModel> playlist, int index) {
    if (index < 0 || index >= playlist.length) return;
    final anime = playlist[index];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnimeDetailScreen(
          anime: anime,
          apiService: widget.apiService,
          onNextMovie: index + 1 < playlist.length
              ? () => _openDetailWithPlaylist(playlist, index + 1)
              : null,
          onPreviousMovie: index > 0
              ? () => _openDetailWithPlaylist(playlist, index - 1)
              : null,
        ),
      ),
    );
  }

  void _playContinueWatching(WatchHistoryItem item) {
    final continueWatching = WatchHistoryService.instance.getContinueWatching(excludeCategory: 'secret');
    final idx = continueWatching.indexWhere((h) => h.id == item.id);
    if (idx != -1) {
      _playContinueWatchingAtIndex(continueWatching, idx);
    } else {
      _playContinueWatchingAtIndex([item], 0);
    }
  }

  void _playContinueWatchingAtIndex(List<WatchHistoryItem> list, int index, {BuildContext? replaceContext}) async {
    if (index < 0 || index >= list.length) return;
    final item = list[index];

    Duration startPos = Duration(milliseconds: item.positionMs);
    if (replaceContext == null) {
      final choice = await ResumePlaybackDialog.show(context, item);
      if (choice == null || !mounted) return;
      startPos = choice ? Duration(milliseconds: item.positionMs) : Duration.zero;
      if (!choice) {
        WatchHistoryService.instance.clearProgress(item.id);
      }
    }

    final hasNextItem = index + 1 < list.length;
    final hasPrevItem = index > 0;
    final isAnimeSeries = (item.category == 'anime' || item.id.startsWith('anime:')) && item.episode > 0 && item.mediaId.isNotEmpty;

    final playerRoute = MaterialPageRoute(
      builder: (playerCtx) => VideoPlayerScreen(
        streamUrl: item.streamUrl,
        title: item.title,
        subtitle: item.episode > 0 ? 'Tập ${item.episode}' : '',
        availableChannels: [
          StreamChannel(
            name: 'Server 1',
            title: item.episode > 0 ? 'Tập ${item.episode}' : item.title,
            url: item.streamUrl,
            headers: const {},
          ),
        ],
        isLive: false,
        initialPosition: startPos,
        mediaId: item.id,
        mediaCategory: item.category,
        mediaPoster: item.poster,
        episode: item.episode,
        season: item.season,
        onNext: isAnimeSeries
            ? () => _loadAndPlayEpisode(
                  list: list,
                  animeId: item.mediaId,
                  animeTitle: item.title,
                  poster: item.poster,
                  season: item.season > 0 ? item.season : 1,
                  episode: item.episode + 1,
                  continueIndex: index,
                  replaceContext: playerCtx,
                )
            : (hasNextItem ? () => _playContinueWatchingAtIndex(list, index + 1, replaceContext: playerCtx) : null),
        onPrevious: isAnimeSeries && item.episode > 1
            ? () => _loadAndPlayEpisode(
                  list: list,
                  animeId: item.mediaId,
                  animeTitle: item.title,
                  poster: item.poster,
                  season: item.season > 0 ? item.season : 1,
                  episode: item.episode - 1,
                  continueIndex: index,
                  replaceContext: playerCtx,
                )
            : (hasPrevItem ? () => _playContinueWatchingAtIndex(list, index - 1, replaceContext: playerCtx) : null),
      ),
    );

    if (replaceContext != null) {
      Navigator.of(replaceContext).pushReplacement(playerRoute);
    } else {
      Navigator.of(context).push(playerRoute);
    }
  }

  void _loadAndPlayEpisode({
    required List<WatchHistoryItem> list,
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
        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
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
      if (continueIndex + 1 < list.length) {
        _playContinueWatchingAtIndex(list, continueIndex + 1, replaceContext: replaceContext);
      }
      return;
    }

    final first = streams.first;
    final channels = streams;

    final hasNextInList = continueIndex + 1 < list.length;
    final hasPrevInList = continueIndex > 0;

    final playerRoute = MaterialPageRoute(
      builder: (playerCtx) => VideoPlayerScreen(
        streamUrl: first.url,
        title: animeTitle,
        subtitle: 'Tập $episode',
        availableChannels: channels,
        isLive: false,
        headers: first.headers,
        mediaId: 'anime:$animeId:ep:$episode',
        mediaCategory: 'anime',
        mediaPoster: poster,
        episode: episode,
        season: season,
        onNext: () => _loadAndPlayEpisode(
          list: list,
          animeId: animeId,
          animeTitle: animeTitle,
          poster: poster,
          season: season,
          episode: episode + 1,
          continueIndex: continueIndex,
          replaceContext: playerCtx,
        ),
        onPrevious: episode > 1
            ? () => _loadAndPlayEpisode(
                  list: list,
                  animeId: animeId,
                  animeTitle: animeTitle,
                  poster: poster,
                  season: season,
                  episode: episode - 1,
                  continueIndex: continueIndex,
                  replaceContext: playerCtx,
                )
            : (hasPrevInList ? () => _playContinueWatchingAtIndex(list, continueIndex - 1, replaceContext: playerCtx) : null),
      ),
    );

    if (replaceContext != null) {
      Navigator.of(replaceContext).pushReplacement(playerRoute);
    } else {
      Navigator.of(context).push(playerRoute);
    }
  }

  void _openContinueWatchingMenu(WatchHistoryItem item) async {
    final favId = 'anime:${item.id.replaceAll(RegExp(r'^anime:|:ep:\d+$'), '')}';
    final isFav = FavoritesService.instance.isFavorite(favId) ||
        FavoritesService.instance.isFavorite(item.id);

    final action = await MovieActionDialog.show(
      context,
      title: item.title,
      poster: item.poster,
      isFavorite: isFav,
      hasHistory: true,
    );

    if (action == null || action == MovieAction.cancel) return;

    if (action == MovieAction.toggleFavorite) {
      final nowFav = FavoritesService.instance.toggleFavorite(
        FavoriteItem(
          id: favId,
          title: item.title,
          poster: item.poster,
          category: 'anime',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      SyncService.schedulePush(widget.apiService.baseUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowFav ? 'Đã thêm vào danh sách Yêu thích ❤️' : 'Đã xóa khỏi danh sách Yêu thích 💔'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF0284C7),
          ),
        );
      }
    } else if (action == MovieAction.removeHistory) {
      WatchHistoryService.instance.clearProgress(item.id);
      SyncService.schedulePush(widget.apiService.baseUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa khỏi danh sách đã xem 🗑️'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      }
    } else if (action == MovieAction.play) {
      _playContinueWatching(item);
    }
  }

  void _openAnimeMenu(AnimeModel anime) async {
    // Nếu ở Toàn Bộ và click vào danh mục đại diện (Pokemon, Sentai...) thì chuyển danh mục
    if (_selectedCategoryIndex == 0 && _findCategoryIndexForAnime(anime) != -1) {
      _loadCategory(_findCategoryIndexForAnime(anime));
      return;
    }

    final favId = 'anime:${anime.id}';
    final isFav = FavoritesService.instance.isFavorite(favId) ||
        FavoritesService.instance.isFavorite(anime.id);
    final hasHist = WatchHistoryService.instance.hasProgressForPrefix(favId) ||
        WatchHistoryService.instance.hasProgressForPrefix(anime.id) ||
        WatchHistoryService.instance.getProgress(favId) != null ||
        WatchHistoryService.instance.getProgress(anime.id) != null;

    final action = await MovieActionDialog.show(
      context,
      title: anime.name,
      poster: anime.poster,
      isFavorite: isFav,
      hasHistory: hasHist,
    );

    if (action == null || action == MovieAction.cancel) return;

    if (action == MovieAction.toggleFavorite) {
      final nowFav = FavoritesService.instance.toggleFavorite(
        FavoriteItem(
          id: favId,
          title: anime.name,
          poster: anime.poster,
          category: 'anime',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      SyncService.schedulePush(widget.apiService.baseUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowFav ? 'Đã thêm vào danh sách Yêu thích ❤️' : 'Đã xóa khỏi danh sách Yêu thích 💔'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF0284C7),
          ),
        );
      }
    } else if (action == MovieAction.removeHistory) {
      WatchHistoryService.instance.clearProgressForPrefix(favId);
      WatchHistoryService.instance.clearProgressForPrefix(anime.id);
      WatchHistoryService.instance.clearProgress(favId);
      WatchHistoryService.instance.clearProgress(anime.id);
      SyncService.schedulePush(widget.apiService.baseUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xóa khỏi danh sách đã xem 🗑️'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      }
    } else if (action == MovieAction.play) {
      _onAnimeCardTap(anime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final continueWatching = WatchHistoryService.instance.getContinueWatching(excludeCategory: 'secret');

    return PopScope(
      canPop: _selectedCategoryIndex == 0,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_selectedCategoryIndex != 0) {
          _loadCategory(0);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Selector Row (Remote Navigable)
          Container(
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _categories.length,
              itemBuilder: (context, idx) {
                final cat = _categories[idx];
                final bool isSelected = idx == _selectedCategoryIndex;

                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: TvFocusableCard(
                    onTap: () => _loadCategory(idx),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: isSelected
                            ? Border.all(color: const Color(0xFF38BDF8), width: 1.2)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        cat['name']!,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Continue Watching Row (Tiếp tục xem)
          if (continueWatching.isNotEmpty)
            _buildContinueWatchingRow(continueWatching),

          // Grid Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          _categories[_selectedCategoryIndex]['id'] == 'favorites'
                              ? 'Chưa có phim nào trong danh sách Yêu thích.'
                              : 'Không có nội dung trong danh mục này.',
                          style: const TextStyle(color: Colors.white54),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          int crossAxisCount = 2;
                          if (constraints.maxWidth > 1200) {
                            crossAxisCount = 6;
                          } else if (constraints.maxWidth > 900) {
                            crossAxisCount = 5;
                          } else if (constraints.maxWidth > 650) {
                            crossAxisCount = 4;
                          } else if (constraints.maxWidth > 450) {
                            crossAxisCount = 3;
                          }

                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                            cacheExtent: 350,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.68,
                            ),
                            itemCount: _items.length,
                            itemBuilder: (context, idx) {
                              final anime = _items[idx];
                              return _buildAnimeCard(anime, index: idx);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatchingRow(List<WatchHistoryItem> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
          child: Row(
            children: [
              const Icon(Icons.history_toggle_off_rounded, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Tiếp tục xem',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4)),
                ),
                child: Text(
                  '${list.length}',
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
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list.length,
            itemBuilder: (context, idx) {
              final item = list[idx];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TvFocusableCard(
                  onTap: () => _playContinueWatchingAtIndex(list, idx),
                  onLongPress: () => _openContinueWatchingMenu(item),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail with Progress bar
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                child: CachedNetworkImage(
                                  imageUrl: item.poster,
                                  memCacheWidth: 200,
                                  memCacheHeight: 120,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: const Color(0xFF334155),
                                    child: const Icon(Icons.movie_outlined, color: Colors.white30, size: 28),
                                  ),
                                ),
                              ),
                              // Play overlay icon
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white30),
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                ),
                              ),
                              // Progress bar
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 4,
                                  color: Colors.black54,
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: item.progressPercent.clamp(0.0, 1.0),
                                    child: Container(
                                      color: const Color(0xFF38BDF8),
                                    ),
                                  ),
                                ),
                              ),
                              // Episode badge if present
                              if (item.episode > 0)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.75),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Tập ${item.episode}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Title + Duration info
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.formattedPosition} / ${item.formattedDuration}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
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
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildAnimeCard(AnimeModel anime, {int? index}) {
    final favId = 'anime:${anime.id}';
    final isFav = FavoritesService.instance.isFavorite(favId) ||
        FavoritesService.instance.isFavorite(anime.id);
    final hasHist = WatchHistoryService.instance.hasProgressForPrefix(favId) ||
        WatchHistoryService.instance.hasProgressForPrefix(anime.id) ||
        WatchHistoryService.instance.getProgress(favId) != null ||
        WatchHistoryService.instance.getProgress(anime.id) != null;

    return TvFocusableCard(
      onTap: () {
        if (index != null && _selectedCategoryIndex != 0) {
          _openDetailWithPlaylist(_items, index);
        } else {
          _onAnimeCardTap(anime);
        }
      },
      onLongPress: () => _openAnimeMenu(anime),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: const Color(0xFF1E293B),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: anime.poster,
                    memCacheWidth: 200,
                    memCacheHeight: 300,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF334155),
                      child: const Icon(Icons.movie_creation_outlined, color: Colors.white30, size: 36),
                    ),
                  ),
                  // Badge icon đồng hồ ở góc trên bên trái nếu đã xem
                  if (hasHist)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5), width: 0.8),
                        ),
                        child: const Icon(Icons.access_time_rounded, color: Color(0xFF38BDF8), size: 12),
                      ),
                    ),
                  // Badge icon tim đỏ nếu đã yêu thích
                  if (isFav)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4),
                          ],
                        ),
                        child: const Icon(Icons.favorite, color: Colors.white, size: 12),
                      ),
                    ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                anime.name,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
