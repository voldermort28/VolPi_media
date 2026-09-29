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
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<MovieModel> _movies = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSearching = false;
  String? _searchQuery;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMovies();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _movies.clear();
    widget.onExit();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadMoreMovies();
      }
    }
  }

  Future<void> _loadMovies({String? search}) async {
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _hasMore = true;
      _searchQuery = search;
    });

    final results = await widget.apiService.getVlxxCatalog(searchQuery: search, skip: 0);
    if (mounted) {
      setState(() {
        _movies = results;
        _isLoading = false;
        if (results.length < 30) {
          _hasMore = false;
        }
      });
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    final currentSkip = _movies.length;
    final nextResults = await widget.apiService.getVlxxCatalog(
      searchQuery: _searchQuery,
      skip: currentSkip,
    );

    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (nextResults.isEmpty) {
          _hasMore = false;
        } else {
          final existingIds = _movies.map((m) => m.id).toSet();
          final uniqueNew = nextResults.where((m) => !existingIds.contains(m.id)).toList();
          if (uniqueNew.isEmpty) {
            _hasMore = false;
          } else {
            _movies.addAll(uniqueNew);
            if (nextResults.length < 30) {
              _hasMore = false;
            }
          }
        }
      });
    }
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _loadMovies(search: query);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
    });
    _loadMovies();
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
                    autoFocus: !_isSearching,
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
                  Text(
                    _searchQuery != null && _searchQuery!.isNotEmpty
                        ? 'Tìm: "$_searchQuery"'
                        : 'Kho Phim Riêng Tư',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),

                  // Search toggle button or search input
                  if (_isSearching)
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 38,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF43F5E), width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Colors.white54, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Nhập từ khóa, mã phim...',
                                  hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onSubmitted: (_) => _submitSearch(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _clearSearch,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    TvFocusableCard(
                      onTap: () {
                        setState(() {
                          _isSearching = true;
                        });
                        Future.delayed(const Duration(milliseconds: 100), () {
                          _searchFocusNode.requestFocus();
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        color: const Color(0xFF1E293B),
                        child: const Row(
                          children: [
                            Icon(Icons.search, color: Colors.white70, size: 16),
                            SizedBox(width: 6),
                            Text('Tìm kiếm', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(width: 10),

                  // Exit & Lock button
                  TvFocusableCard(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

            // Content Grid with Infinite Scroll
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF43F5E)))
                  : _movies.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off, size: 48, color: Colors.white38),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery != null ? 'Không tìm thấy phim phù hợp với "$_searchQuery"' : 'Không tìm thấy phim.',
                                style: const TextStyle(color: Colors.white54, fontSize: 14),
                              ),
                              if (_searchQuery != null) ...[
                                const SizedBox(height: 16),
                                TvFocusableCard(
                                  onTap: _clearSearch,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    color: const Color(0xFF1E293B),
                                    child: const Text('Xem tất cả phim', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ),
                                ),
                              ],
                            ],
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

                            return CustomScrollView(
                              controller: _scrollController,
                              slivers: [
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  sliver: SliverGrid(
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 16,
                                      childAspectRatio: 0.68,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, idx) {
                                        // Auto-prefetch when reaching near end on TV Remote D-pad
                                        if (idx >= _movies.length - crossAxisCount &&
                                            !_isLoading &&
                                            !_isLoadingMore &&
                                            _hasMore) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted && !_isLoading && !_isLoadingMore && _hasMore) {
                                              _loadMoreMovies();
                                            }
                                          });
                                        }

                                        final movie = _movies[idx];
                                        return _buildMovieCard(movie);
                                      },
                                      childCount: _movies.length,
                                    ),
                                  ),
                                ),

                                // Bottom Loading Indicator
                                if (_isLoadingMore)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Color(0xFFF43F5E),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text(
                                              'Đang tải thêm phim...',
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                // End of catalog message
                                if (!_hasMore && _movies.isNotEmpty)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(vertical: 28),
                                      child: Center(
                                        child: Text(
                                          '🎉 Đã hiển thị toàn bộ danh sách phim',
                                          style: TextStyle(color: Colors.white38, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
