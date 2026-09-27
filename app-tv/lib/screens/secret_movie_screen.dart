import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/movie_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class SecretMovieScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onExit;

  const SecretMovieScreen({
    super.key,
    required this.apiService,
    required this.onExit,
  });

  @override
  State<SecretMovieScreen> createState() => _SecretMovieScreenState();
}

class _SecretMovieScreenState extends State<SecretMovieScreen> {
  List<MovieModel> _movies = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String? _searchQuery;

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  @override
  void dispose() {
    // ZERO-TRACE: Wipe controller & local list from memory
    _searchController.dispose();
    _movies.clear();
    widget.onExit();
    super.dispose();
  }

  Future<void> _loadMovies({String? search}) async {
    setState(() {
      _isLoading = true;
      _searchQuery = search;
    });

    final results = await widget.apiService.getVlxxCatalog(searchQuery: search);
    if (mounted) {
      setState(() {
        _movies = results;
        _isLoading = false;
      });
    }
  }

  void _onMovieSelected(MovieModel movie) {
    final servers = widget.apiService.getVlxxStreams(movie.rawId);

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
                      movie.title,
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
                'Chọn máy chủ phát (Full HD không quảng cáo):',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListView.separated(
                shrinkWrap: true,
                itemCount: servers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, idx) {
                  final s = servers[idx];
                  return TvFocusableCard(
                    autoFocus: idx == 0,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _playMovieStream(movie, s);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: const Color(0xFF1E293B),
                      child: Row(
                        children: [
                          const Icon(Icons.play_circle_fill, color: Color(0xFFF43F5E), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              s.title,
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
            ],
          ),
        );
      },
    );
  }

  void _playMovieStream(MovieModel movie, dynamic server) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: server.url,
          title: movie.title,
          subtitle: server.title,
          isLive: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Header Bar
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
                  const SizedBox(width: 12),
                  const Text('🎬', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  const Text(
                    'Kho Phim Riêng Tư',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  // Exit & Lock button
                  TvFocusableCard(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: Colors.redAccent.withOpacity(0.2),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, color: Colors.redAccent, size: 16),
                          SizedBox(width: 6),
                          Text('Khóa & Thoát', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Content Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF43F5E)))
                  : _movies.isEmpty
                      ? const Center(child: Text('Không tìm thấy phim.', style: TextStyle(color: Colors.white54)))
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
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 16,
                                childAspectRatio: 0.68,
                              ),
                              itemCount: _movies.length,
                              itemBuilder: (context, idx) {
                                final movie = _movies[idx];
                                return _buildMovieCard(movie);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieCard(MovieModel movie) {
    return TvFocusableCard(
      onTap: () => _onMovieSelected(movie),
      focusBorderColor: const Color(0xFFF43F5E),
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
                    imageUrl: movie.poster,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFF334155),
                      child: const Icon(Icons.movie_outlined, color: Colors.white30, size: 36),
                    ),
                  ),
                  if (movie.ribbon.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          movie.ribbon,
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
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
                movie.title,
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
