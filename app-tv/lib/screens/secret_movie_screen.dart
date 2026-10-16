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
  final ScrollController _genreScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Tab 0: VLFilm, Tab 1: Viet69
  int _selectedSourceIndex = 0;
  String _selectedGenre = 'Tất cả';

  final List<String> _viet69Genres = const [
    'Tất cả',
    'Phim sex Việt mới',
    'Sinh viên',
    'Teen',
    'Check hàng',
    'Camera',
    'BDSM',
    'Máy bay bà già',
    'Thủ dâm',
  ];

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
    _genreScrollController.dispose();
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

    List<MovieModel> results = [];
    if (_selectedSourceIndex == 0) {
      // VLFilm
      results = await widget.apiService.getVlxxCatalog(searchQuery: search, skip: 0);
    } else {
      // Viet69
      results = await widget.apiService.getViet69Catalog(
        searchQuery: search,
        skip: 0,
        genre: _selectedGenre,
      );
    }

    if (mounted) {
      setState(() {
        _movies = results;
        _isLoading = false;
        if (results.length < 20) {
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
    List<MovieModel> nextResults = [];

    if (_selectedSourceIndex == 0) {
      nextResults = await widget.apiService.getVlxxCatalog(
        searchQuery: _searchQuery,
        skip: currentSkip,
      );
    } else {
      nextResults = await widget.apiService.getViet69Catalog(
        searchQuery: _searchQuery,
        skip: currentSkip,
        genre: _selectedGenre,
      );
    }

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
            if (nextResults.length < 20) {
              _hasMore = false;
            }
          }
        }
      });
    }
  }

  void _switchSource(int index) {
    if (_selectedSourceIndex == index) return;
    setState(() {
      _selectedSourceIndex = index;
      _selectedGenre = 'Tất cả';
      _isSearching = false;
      _searchController.clear();
      _searchQuery = null;
    });
    _loadMovies();
  }

  void _selectGenre(String genre) {
    if (_selectedGenre == genre) return;
    setState(() {
      _selectedGenre = genre;
      _isSearching = false;
      _searchController.clear();
      _searchQuery = null;
    });
    _loadMovies();
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

  void _playMovieAtIndex(int index, {BuildContext? replaceContext}) {
    if (index < 0 || index >= _movies.length) return;

    final movie = _movies[index];
    final bool isViet69 = _selectedSourceIndex == 1 || movie.id.startsWith('viet69:');
    final List<StreamChannel> servers = isViet69
        ? widget.apiService.getViet69Streams(movie.rawId)
        : widget.apiService.getVlxxStreams(movie.rawId);

    if (servers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy link phát cho phim này.')),
      );
      return;
    }

    final initialServer = servers.first;

    // Auto-prefetch more movies if nearing the end
    if (index >= _movies.length - 3 && _hasMore && !_isLoadingMore) {
      _loadMoreMovies();
    }

    final playerRoute = MaterialPageRoute(
      builder: (playerCtx) => VideoPlayerScreen(
        streamUrl: initialServer.url,
        title: movie.title,
        subtitle: initialServer.title,
        headers: initialServer.headers,
        availableChannels: servers,
        isLive: false,
        onNext: index + 1 < _movies.length
            ? () => _playMovieAtIndex(index + 1, replaceContext: playerCtx)
            : null,
        onPrevious: index > 0
            ? () => _playMovieAtIndex(index - 1, replaceContext: playerCtx)
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
    final themeColor = _selectedSourceIndex == 1 ? const Color(0xFFEA580C) : const Color(0xFFF43F5E);

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

                  // TAB SWITCHER: VLFilm vs Viet69
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSourceTab(
                          index: 0,
                          label: 'VLFilm',
                          icon: Icons.movie_outlined,
                          activeColor: const Color(0xFFF43F5E),
                        ),
                        const SizedBox(width: 4),
                        _buildSourceTab(
                          index: 1,
                          label: 'Viet69',
                          icon: Icons.local_fire_department_rounded,
                          activeColor: const Color(0xFFEA580C),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),
                  if (_searchQuery != null && _searchQuery!.isNotEmpty)
                    Expanded(
                      child: Text(
                        'Tìm: "$_searchQuery"',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
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
                          border: Border.all(color: themeColor, width: 1.5),
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
                                decoration: InputDecoration(
                                  hintText: _selectedSourceIndex == 1
                                      ? 'Nhập từ khóa clip, sinh viên, teen...'
                                      : 'Nhập từ khóa, mã phim...',
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
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

            // Category Bar (Only visible when Viet69 tab is active & not in search mode)
            if (_selectedSourceIndex == 1 && (_searchQuery == null || _searchQuery!.isEmpty))
              Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView.separated(
                  controller: _genreScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _viet69Genres.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final genre = _viet69Genres[idx];
                    final bool isSelected = _selectedGenre == genre;
                    return TvFocusableCard(
                      onTap: () => _selectGenre(genre),
                      borderRadius: BorderRadius.circular(20),
                      focusBorderColor: const Color(0xFFEA580C),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEA580C) : const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFEA580C) : Colors.white12,
                          ),
                        ),
                        child: Text(
                          genre,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Content Grid with Infinite Scroll
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: themeColor))
                  : _movies.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off, size: 48, color: Colors.white38),
                              const SizedBox(height: 12),
                              Text(
                                _searchQuery != null
                                    ? 'Không tìm thấy phim phù hợp với "$_searchQuery"'
                                    : 'Không tìm thấy nội dung.',
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
                              cacheExtent: 350,
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
                                        return _buildMovieCard(movie, idx, themeColor);
                                      },
                                      childCount: _movies.length,
                                      addAutomaticKeepAlives: true,
                                    ),
                                  ),
                                ),

                                // Bottom Loading Indicator
                                if (_isLoadingMore)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: themeColor,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Đang tải thêm nội dung...',
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
                                      padding: const EdgeInsets.symmetric(vertical: 28),
                                      child: Center(
                                        child: Text(
                                          '🎉 Đã hiển thị toàn bộ danh sách',
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

  Widget _buildSourceTab({
    required int index,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final bool isSelected = _selectedSourceIndex == index;

    return TvFocusableCard(
      onTap: () => _switchSource(index),
      borderRadius: BorderRadius.circular(9),
      focusBorderColor: activeColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white60, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovieCard(MovieModel movie, int index, Color themeColor) {
    return TvFocusableCard(
      onTap: () => _playMovieAtIndex(index),
      focusBorderColor: themeColor,
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
                    memCacheWidth: 240,
                    memCacheHeight: 160,
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
                          color: themeColor,
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
