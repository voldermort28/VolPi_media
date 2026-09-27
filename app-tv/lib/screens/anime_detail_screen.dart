import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/anime_model.dart';
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

  void _playEpisode(EpisodeModel ep) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
    );

    final streamUrl = await widget.apiService.getAnimeEpisodeStream(
      widget.anime.id,
      ep.season,
      ep.episode,
      type: widget.anime.type,
    );

    if (!mounted) return;
    Navigator.of(context).pop();

    if (streamUrl == null || streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy link phát cho tập này.'), backgroundColor: Colors.amber),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: streamUrl,
          title: widget.anime.name,
          subtitle: 'Tập ${ep.episode}: ${ep.title}',
          isLive: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anime = _detailedAnime ?? widget.anime;
    final episodes = anime.episodes;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster & Description Card (Left Column)
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
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 220,
                                height: 310,
                                color: const Color(0xFF1E293B),
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
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(g, style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10)),
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 10),
                          if (anime.description.isNotEmpty)
                            Text(
                              anime.description,
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.4),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.list_alt_rounded, color: Color(0xFF38BDF8), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Danh Sách Tập (${episodes.length} tập)',
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 110,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          mainAxisExtent: 52,
                                        ),
                                        itemCount: episodes.length,
                                        itemBuilder: (context, idx) {
                                          final ep = episodes[idx];
                                          return TvFocusableCard(
                                            onTap: () => _playEpisode(ep),
                                            borderRadius: BorderRadius.circular(10),
                                            child: Container(
                                              color: const Color(0xFF1E293B),
                                              alignment: Alignment.center,
                                              padding: const EdgeInsets.symmetric(horizontal: 8),
                                              child: Text(
                                                'Tập ${ep.episode}',
                                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                                textAlign: TextAlign.center,
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
