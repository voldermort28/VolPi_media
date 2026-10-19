import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/anime_model.dart';
import '../models/favorite_item_model.dart';
import '../models/match_model.dart';
import '../models/watch_history_model.dart';
import '../services/favorites_service.dart';
import '../services/sync_service.dart';
import '../services/watch_history_service.dart';
import '../widgets/resume_playback_dialog.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class AnimeDetailScreen extends StatefulWidget {
  final AnimeModel anime;
  final ApiService apiService;

  const AnimeDetailScreen({super.key, required this.anime, required this.apiService});

  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen> {
  AnimeModel? _detailedAnime;
  bool _isLoading = true;
  String _selectedVariant = 'DUB'; // 'DUB' for Thuyết Minh, 'SUB' for Phụ Đề

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final res = await widget.apiService.getAnimeDetails(widget.anime.id, type: widget.anime.type);
    if (mounted) {
      setState(() {
        _detailedAnime = res ?? widget.anime;
        _isLoading = false;
      });
    }
  }

  void _playEpisodeAtIndex(int index, {BuildContext? replaceContext}) async {
    final anime = _detailedAnime ?? widget.anime;
    final episodes = anime.episodes;
    if (index < 0 || index >= episodes.length) return;

    final ep = episodes[index];
    final targetContext = replaceContext ?? context;

    final historyId = 'anime:${widget.anime.id}:ep:${ep.episode}';
    final saved = WatchHistoryService.instance.getProgress(historyId);

    Duration? startPosition;
    if (saved != null && saved.isInProgress && replaceContext == null) {
      final choice = await ResumePlaybackDialog.show(context, saved);
      if (choice == null) return; // Hủy
      if (choice) {
        startPosition = Duration(milliseconds: saved.positionMs);
      } else {
        startPosition = Duration.zero;
        WatchHistoryService.instance.clearProgress(historyId);
      }
    }

    showDialog(
      context: targetContext,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
    );

    final streams = await widget.apiService.getAnimeEpisodeStreams(
      widget.anime.id,
      ep.season,
      ep.episode,
      type: widget.anime.type,
    );

    if (!mounted) return;
    Navigator.of(targetContext).pop();

    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy link phát cho tập này.'), backgroundColor: Colors.amber),
      );
      return;
    }

    StreamChannel selectedStream = streams.first;
    if (_selectedVariant == 'SUB') {
      final subMatch = streams.firstWhere(
        (s) => s.title.toLowerCase().contains('phụ đề') || s.title.toLowerCase().contains('sub'),
        orElse: () => streams.first,
      );
      selectedStream = subMatch;
    } else {
      final dubMatch = streams.firstWhere(
        (s) => s.title.toLowerCase().contains('thuyết minh') || s.title.toLowerCase().contains('dub'),
        orElse: () => streams.first,
      );
      selectedStream = dubMatch;
    }

    final variantLabel = _selectedVariant == 'SUB' ? 'Phụ Đề' : 'Thuyết Minh';

    final playerRoute = MaterialPageRoute(
      builder: (playerCtx) => VideoPlayerScreen(
        streamUrl: selectedStream.url,
        title: '${widget.anime.name} ($variantLabel)',
        subtitle: 'Tập ${ep.episode}: ${ep.title}',
        headers: selectedStream.headers,
        availableChannels: streams,
        isLive: false,
        initialPosition: startPosition,
        mediaId: historyId,
        mediaCategory: 'anime',
        mediaPoster: ep.thumbnail.isNotEmpty ? ep.thumbnail : anime.poster,
        episode: ep.episode,
        season: ep.season,
        onNext: index + 1 < episodes.length
            ? () => _playEpisodeAtIndex(index + 1, replaceContext: playerCtx)
            : null,
        onPrevious: index > 0
            ? () => _playEpisodeAtIndex(index - 1, replaceContext: playerCtx)
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
    final anime = _detailedAnime ?? widget.anime;
    final episodes = anime.episodes;

    final bool isNarrow = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 20, vertical: isNarrow ? 8 : 12),
              child: Row(
                children: [
                  TvFocusableCard(
                    autoFocus: true,
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFF1E293B),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      anime.name,
                      style: TextStyle(color: Colors.white, fontSize: isNarrow ? 16 : 18, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: FavoritesService.instance.changeNotifier,
                    builder: (context, _, __) {
                      final favId = 'anime:${widget.anime.id}';
                      final isFav = FavoritesService.instance.isFavorite(favId) ||
                          FavoritesService.instance.isFavorite(widget.anime.id);

                      return TvFocusableCard(
                        onTap: () {
                          final nowFav = FavoritesService.instance.toggleFavorite(
                            FavoriteItem(
                              id: favId,
                              title: widget.anime.name,
                              poster: widget.anime.poster,
                              category: 'anime',
                              createdAt: DateTime.now().toIso8601String(),
                            ),
                          );
                          SyncService.schedulePush(widget.apiService.baseUrl);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                nowFav
                                    ? 'Đã thêm vào danh sách Yêu thích ❤️'
                                    : 'Đã xóa khỏi danh sách Yêu thích 💔',
                              ),
                              duration: const Duration(seconds: 2),
                              backgroundColor: const Color(0xFF0284C7),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isFav ? const Color(0xFFE11D48) : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isFav ? const Color(0xFFFB7185) : Colors.white12,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFav ? Icons.favorite : Icons.favorite_border,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isFav ? 'Đã Thích' : 'Yêu Thích',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster & Description Card (Left Column - compact on mobile)
                  Container(
                    width: isNarrow ? 120 : 260,
                    padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 20),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(isNarrow ? 8 : 12),
                            child: CachedNetworkImage(
                              imageUrl: anime.poster,
                              width: isNarrow ? 104 : 220,
                              height: isNarrow ? 148 : 310,
                              memCacheWidth: isNarrow ? 130 : 220,
                              memCacheHeight: isNarrow ? 180 : 310,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: isNarrow ? 104 : 220,
                                height: isNarrow ? 148 : 310,
                                color: const Color(0xFF1E293B),
                                child: Icon(Icons.movie_outlined, size: isNarrow ? 32 : 48, color: Colors.white30),
                              ),
                            ),
                          ),
                          SizedBox(height: isNarrow ? 8 : 12),
                          if (anime.genres.isNotEmpty)
                            Wrap(
                              spacing: isNarrow ? 4 : 6,
                              runSpacing: isNarrow ? 4 : 6,
                              children: anime.genres.map((g) {
                                return Container(
                                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 5 : 8, vertical: isNarrow ? 2 : 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(g, style: TextStyle(color: const Color(0xFF38BDF8), fontSize: isNarrow ? 9 : 10)),
                                );
                              }).toList(),
                            ),
                          SizedBox(height: isNarrow ? 6 : 10),
                          if (anime.description.isNotEmpty)
                            Text(
                              anime.description,
                              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: isNarrow ? 11 : 12, height: 1.3),
                              maxLines: isNarrow ? 4 : 6,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Episodes Grid (Right Column)
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.only(right: isNarrow ? 10 : 20, bottom: isNarrow ? 12 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.list_alt_rounded, color: Color(0xFF38BDF8), size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    isNarrow ? 'Tập (${episodes.length})' : 'Danh Sách Tập (${episodes.length} tập)',
                                    style: TextStyle(color: Colors.white, fontSize: isNarrow ? 13 : 15, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              // Folder Switchers: Thuyet Minh & Phu De
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TvFocusableCard(
                                    onTap: () {
                                      setState(() {
                                        _selectedVariant = 'DUB';
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 12, vertical: isNarrow ? 4 : 6),
                                      color: _selectedVariant == 'DUB' ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.record_voice_over_rounded,
                                            size: isNarrow ? 12 : 14,
                                            color: _selectedVariant == 'DUB' ? Colors.white : Colors.white70,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isNarrow ? 'TM' : '🎙️ Thuyết Minh',
                                            style: TextStyle(
                                              color: _selectedVariant == 'DUB' ? Colors.white : Colors.white70,
                                              fontSize: isNarrow ? 11 : 12,
                                              fontWeight: _selectedVariant == 'DUB' ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  TvFocusableCard(
                                    onTap: () {
                                      setState(() {
                                        _selectedVariant = 'SUB';
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 12, vertical: isNarrow ? 4 : 6),
                                      color: _selectedVariant == 'SUB' ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.subtitles_rounded,
                                            size: isNarrow ? 12 : 14,
                                            color: _selectedVariant == 'SUB' ? Colors.white : Colors.white70,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isNarrow ? 'Sub' : '📝 Phụ Đề',
                                            style: TextStyle(
                                              color: _selectedVariant == 'SUB' ? Colors.white : Colors.white70,
                                              fontSize: isNarrow ? 11 : 12,
                                              fontWeight: _selectedVariant == 'SUB' ? FontWeight.bold : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                                : episodes.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'Chưa có tập phim hoặc là phim lẻ (bấm để xem).',
                                          style: TextStyle(color: Colors.white54, fontSize: 13),
                                        ),
                                      )
                                    : GridView.builder(
                                        cacheExtent: 250,
                                        addAutomaticKeepAlives: true,
                                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: isNarrow ? 76 : 110,
                                          crossAxisSpacing: isNarrow ? 6 : 10,
                                          mainAxisSpacing: isNarrow ? 6 : 10,
                                          mainAxisExtent: isNarrow ? 42 : 52,
                                        ),
                                        itemCount: episodes.length,
                                        itemBuilder: (context, idx) {
                                          final ep = episodes[idx];
                                          final epHistoryId = 'anime:${anime.id}:ep:${ep.episode}';
                                          final epSaved = WatchHistoryService.instance.getProgress(epHistoryId);
                                          return TvFocusableCard(
                                            onTap: () => _playEpisodeAtIndex(idx),
                                            borderRadius: BorderRadius.circular(isNarrow ? 8 : 10),
                                            child: Container(
                                              color: const Color(0xFF1E293B),
                                              alignment: Alignment.center,
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Text(
                                                    'Tập ${ep.episode}',
                                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  if (epSaved != null)
                                                    Positioned(
                                                      bottom: 2,
                                                      left: 4,
                                                      right: 4,
                                                      child: ClipRRect(
                                                        borderRadius: BorderRadius.circular(2),
                                                        child: LinearProgressIndicator(
                                                          value: epSaved.isInProgress ? epSaved.progressPercent : 1.0,
                                                          minHeight: 2.5,
                                                          backgroundColor: Colors.white10,
                                                          valueColor: AlwaysStoppedAnimation(
                                                            epSaved.isInProgress ? const Color(0xFF38BDF8) : const Color(0xFF10B981),
                                                          ),
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
