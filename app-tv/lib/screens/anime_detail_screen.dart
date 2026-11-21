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
import '../widgets/loading_dialog_helper.dart';
import '../widgets/resume_playback_dialog.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class AnimeDetailScreen extends StatefulWidget {
  final AnimeModel anime;
  final ApiService apiService;
  final VoidCallback? onNextMovie;
  final VoidCallback? onPreviousMovie;

  const AnimeDetailScreen({
    super.key,
    required this.anime,
    required this.apiService,
    this.onNextMovie,
    this.onPreviousMovie,
  });

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
    WatchHistoryService.instance.changeNotifier.addListener(_onHistoryChanged);
    _loadDetails();
  }

  @override
  void dispose() {
    WatchHistoryService.instance.changeNotifier.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _playSingleMovie() async {
    final anime = _detailedAnime ?? widget.anime;
    final cleanId = anime.id.replaceAll(RegExp(r'^anime:'), '');
    final streams = await LoadingDialogHelper.runWithLoading(
      context,
      () => widget.apiService.getAnimeEpisodeStreams(cleanId, 1, 1, type: anime.type),
    );
    if (!mounted || streams == null) return;
    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy link phát cho phim này.'), backgroundColor: Colors.amber),
      );
      return;
    }
    final selected = streams.first;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: selected.url,
          title: anime.name,
          subtitle: selected.title,
          headers: selected.headers,
          availableChannels: streams,
          isLive: false,
          mediaId: 'anime:$cleanId:ep:1',
          mediaCategory: 'anime',
          mediaPoster: anime.poster,
          episode: 1,
          season: 1,
        ),
      ),
    );
  }

  Future<void> _loadDetails() async {
    final cleanId = widget.anime.id.replaceAll(RegExp(r'^anime:'), '').replaceAll(RegExp(r':ep:\d+.*$'), '').replaceAll(RegExp(r':\d+:\d+$'), '');
    final res = await widget.apiService.getAnimeDetails(cleanId, type: widget.anime.type);
    if (mounted) {
      setState(() {
        _detailedAnime = res ?? widget.anime;
        _isLoading = false;
      });
    }
  }

  void _playEpisodeAtIndex(int index, {BuildContext? replaceContext, bool resumeDirectly = false}) async {
    final anime = _detailedAnime ?? widget.anime;
    final episodes = anime.episodes;
    if (index < 0 || index >= episodes.length) return;

    final ep = episodes[index];
    final targetContext = replaceContext ?? context;

    final historyId = 'anime:${widget.anime.id}:ep:${ep.episode}';
    final saved = WatchHistoryService.instance.getProgress(historyId);

    Duration? startPosition;
    if (saved != null && saved.isInProgress) {
      if (resumeDirectly) {
        startPosition = Duration(milliseconds: saved.positionMs);
      } else if (replaceContext == null) {
        final hasNext = index + 1 < episodes.length;
        final choice = await ResumePlaybackDialog.show(
          context,
          saved,
          hasNextEpisode: hasNext,
          nextEpisodeNumber: hasNext ? episodes[index + 1].episode : null,
        );
        if (choice == null || !mounted) return; // Hủy
        if (choice == ResumeChoice.nextEpisode) {
          _playEpisodeAtIndex(index + 1);
          return;
        }
        if (choice == ResumeChoice.resume) {
          startPosition = Duration(milliseconds: saved.positionMs);
        } else {
          startPosition = Duration.zero;
          WatchHistoryService.instance.clearProgress(historyId);
        }
      }
    }

    if (!targetContext.mounted) return;
    final streams = await LoadingDialogHelper.runWithLoading(
      targetContext,
      () => widget.apiService.getAnimeEpisodeStreams(
        widget.anime.id,
        ep.season,
        ep.episode,
        type: widget.anime.type,
      ),
      indicatorColor: const Color(0xFF38BDF8),
    );

    if (!mounted || !targetContext.mounted || streams == null) return;

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
        episodes: episodes,
        currentEpisodeIndex: index,
        onSelectEpisode: (newIdx) => _playEpisodeAtIndex(newIdx, replaceContext: playerCtx),
        onNext: index + 1 < episodes.length
            ? () => _playEpisodeAtIndex(index + 1, replaceContext: playerCtx)
            : null,
        onPrevious: index > 0
            ? () => _playEpisodeAtIndex(index - 1, replaceContext: playerCtx)
            : null,
      ),
    );

    if (replaceContext != null) {
      if (replaceContext.mounted) {
        Navigator.of(replaceContext).pushReplacement(playerRoute);
      }
    } else if (mounted) {
      Navigator.of(context).push(playerRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anime = _detailedAnime ?? widget.anime;
    final episodes = anime.episodes;

    final bool isNarrow = MediaQuery.of(context).size.width < 600;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (VideoPlayerScreen.isRecentExit()) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 20, vertical: isNarrow ? 8 : 12),
                child: Row(
                  children: [
                    TvFocusableCard(
                      autoFocus: false,
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

            // Content Area (Stacked header on portrait phones so episodes get full width; 2 columns on TV/landscape)
            Expanded(
              child: isNarrow
                  ? Column(
                      children: [
                        // Compact Mobile Poster & Info Row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: anime.poster,
                                  width: 82,
                                  height: 118,
                                  memCacheWidth: 160,
                                  memCacheHeight: 230,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    width: 82,
                                    height: 118,
                                    color: const Color(0xFF1A1A1A),
                                    child: const Icon(Icons.movie_outlined, size: 28, color: Colors.white30),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (anime.genres.isNotEmpty)
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: anime.genres.take(4).map((g) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1E293B),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(g, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
                                          );
                                        }).toList(),
                                      ),
                                    if (anime.description.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        anime.description,
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.35),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: _buildEpisodesColumn(anime, episodes, isNarrow),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster & Description Card (Left Column on TV / Tablet / Desktop)
                        Container(
                          width: 260,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedNetworkImage(
                                    imageUrl: anime.poster,
                                    width: 220,
                                    height: 310,
                                    memCacheWidth: 220,
                                    memCacheHeight: 310,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      width: 220,
                                      height: 310,
                                      color: const Color(0xFF1A1A1A),
                                      child: const Icon(Icons.movie_outlined, size: 48, color: Colors.white30),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (anime.genres.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: anime.genres.map((g) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E293B),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(g, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
                                      );
                                    }).toList(),
                                  ),
                                const SizedBox(height: 10),
                                if (anime.description.isNotEmpty)
                                  Text(
                                    anime.description,
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.3),
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // Episodes Grid (Right Column)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.only(right: 20, bottom: 20),
                            child: _buildEpisodesColumn(anime, episodes, isNarrow),
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
  }

  Widget _buildEpisodesColumn(AnimeModel anime, List<EpisodeModel> episodes, bool isNarrow) {
    return Column(
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
                          ValueListenableBuilder<int>(
                            valueListenable: WatchHistoryService.instance.changeNotifier,
                            builder: (context, _, __) {
                              final latestProgress = WatchHistoryService.instance.getLatestProgressForMedia(widget.anime.id);
                              if (latestProgress == null || !latestProgress.isInProgress || episodes.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              final targetIdx = episodes.indexWhere((e) => e.episode == latestProgress.episode);
                              final playIdx = targetIdx != -1 ? targetIdx : 0;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TvFocusableCard(
                                  onTap: () => _playEpisodeAtIndex(playIdx, resumeDirectly: true),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isNarrow ? 10 : 14,
                                      vertical: isNarrow ? 8 : 10,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF0284C7).withOpacity(0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.play_circle_filled_rounded, color: Colors.white, size: 22),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                latestProgress.episode > 0
                                                    ? 'Tiếp tục xem: Tập ${latestProgress.episode}'
                                                    : 'Tiếp tục xem phim',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: isNarrow ? 12 : 13,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Đang dừng ở ${latestProgress.formattedPosition} / ${latestProgress.formattedDuration} (bấm để xem tiếp)',
                                                style: TextStyle(
                                                  color: Colors.white.withOpacity(0.85),
                                                  fontSize: isNarrow ? 10 : 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 12),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                                : episodes.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'Phim lẻ hoặc chưa phân danh sách tập',
                                              style: TextStyle(color: Colors.white60, fontSize: 13),
                                            ),
                                            const SizedBox(height: 14),
                                            TvFocusableCard(
                                              autoFocus: true,
                                              onTap: _playSingleMovie,
                                              borderRadius: BorderRadius.circular(10),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE50914),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                                    SizedBox(width: 6),
                                                    Text(
                                                      'Phát Phim Ngay',
                                                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
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
                                              autoFocus: idx == 0,
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
                      );
  }
}
