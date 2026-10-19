import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../api/api_service.dart';
import '../../models/anime_model.dart';
import '../../models/favorite_item_model.dart';
import '../../models/watch_history_model.dart';
import '../../player/video_player_screen.dart';
import '../../services/favorites_service.dart';
import '../../services/watch_history_service.dart';
import '../../widgets/movie_action_dialog.dart';
import '../../widgets/netflix/netflix_scrollable_row.dart';
import '../../widgets/resume_playback_dialog.dart';
import '../../widgets/tv_focusable_card.dart';
import '../anime_detail_screen.dart';

class NetflixAnimeScreen extends StatefulWidget {
  final ApiService apiService;
  final ValueChanged<int>? onNavigateTab;

  const NetflixAnimeScreen({
    super.key,
    required this.apiService,
    this.onNavigateTab,
  });

  @override
  NetflixAnimeScreenState createState() => NetflixAnimeScreenState();
}

class NetflixAnimeScreenState extends State<NetflixAnimeScreen> {
  Future<void> refresh() => _loadAllData();

  final List<Map<String, String>> _categories = const [
    {
      'id': 'yumei-pokemon',
      'title': '⚡ POKÉMON SERIES',
      'badge': '29 MÙA & HORIZONS',
      'icon': '🔴',
    },
    {
      'id': 'yumei-sentai',
      'title': '⚔️ SUPER SENTAI (SIÊU NHÂN)',
      'badge': '18 SERIES',
      'icon': '⚡',
    },
    {
      'id': 'yumei-power-rangers',
      'title': '⚡ POWER RANGERS',
      'badge': 'BIỆT KÍCH',
      'icon': '🛡️',
    },
    {
      'id': 'yumei-anime',
      'title': '🌸 ANIME TUỔI THƠ & NỔI BẬT',
      'badge': 'HUYỀN THOẠI',
      'icon': '✨',
    },
    {
      'id': 'yumei-movies',
      'title': '🎬 PHIM LẺ & CHIẾU RẠP ANIME',
      'badge': 'THE MOVIES',
      'icon': '🍿',
    },
  ];

  final Map<String, List<AnimeModel>> _catalogData = {};
  List<WatchHistoryItem> _continueWatching = [];
  List<AnimeModel> _favorites = [];
  List<AnimeModel> _featuredList = [];
  int _currentBannerIndex = 0;
  final PageController _bannerPageController = PageController();
  Timer? _bannerTimer;
  bool _isBannerInteracting = false;
  bool _isLoading = true;
  String? _errorMessage;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _billboardPlayFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.changeNotifier.addListener(_onHistoryOrFavoritesChanged);
    FavoritesService.instance.changeNotifier.addListener(_onHistoryOrFavoritesChanged);
    _loadAllData();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerPageController.dispose();
    _scrollController.dispose();
    WatchHistoryService.instance.changeNotifier.removeListener(_onHistoryOrFavoritesChanged);
    FavoritesService.instance.changeNotifier.removeListener(_onHistoryOrFavoritesChanged);
    _billboardPlayFocusNode.dispose();
    super.dispose();
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

  void _onHistoryOrFavoritesChanged() {
    if (!mounted) return;
    _updateHistoryAndFavorites();
  }

  void _updateHistoryAndFavorites() {
    final allHistory = WatchHistoryService.instance.getContinueWatching(excludeCategory: 'secret');
    final animeHistory = allHistory.where((item) {
      final id = item.id.toLowerCase();
      final cat = item.category.toLowerCase();
      return cat == 'anime' || id.startsWith('anime:') || id.startsWith('yumei:');
    }).toList();

    final allFavs = FavoritesService.instance.getFavorites().where((f) => f.category != 'secret').toList();
    final animeFavs = allFavs.map<AnimeModel>((f) {
      final cleanId = f.id.startsWith('anime:') ? f.id.substring(6) : f.id;
      return AnimeModel(
        id: cleanId,
        name: f.title,
        poster: f.poster,
        background: f.poster,
        description: '',
      );
    }).toList();

    setState(() {
      _continueWatching = animeHistory;
      _favorites = animeFavs;
    });
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _updateHistoryAndFavorites();

    try {
      final futures = _categories.map((cat) => widget.apiService.getAnimeCatalog(cat['id']!));
      final results = await Future.wait(futures);

      if (!mounted) return;

      for (int i = 0; i < _categories.length; i++) {
        _catalogData[_categories[i]['id']!] = results[i];
      }

      // Select Featured Billboard Anime (random pool of 6 items)
      final pool = <AnimeModel>[];
      for (final list in _catalogData.values) {
        for (final anime in list) {
          if (anime.background.isNotEmpty && anime.background != anime.poster) {
            pool.add(anime);
          }
        }
      }
      if (pool.length < 6) {
        for (final list in _catalogData.values) {
          for (final anime in list) {
            if (!pool.any((item) => item.id == anime.id)) {
              pool.add(anime);
            }
          }
        }
      }
      pool.shuffle(Random());
      final featured = pool.take(6).toList();

      setState(() {
        _featuredList = featured;
        _currentBannerIndex = 0;
        _isLoading = false;
      });

      _startBannerTimer();

      // Auto-focus billboard play button for TV Remote
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _featuredList.isNotEmpty) {
          _billboardPlayFocusNode.requestFocus();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể tải danh mục Anime & Phim: $e';
        });
      }
    }
  }

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    if (_featuredList.length <= 1) return;
    _bannerTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (!mounted || _isBannerInteracting) return;
      if (_bannerPageController.hasClients) {
        final nextIndex = (_currentBannerIndex + 1) % _featuredList.length;
        _bannerPageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      }
    });
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

  void _playContinueWatching(WatchHistoryItem item) async {
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
            isLive: false,
            initialPosition: startPos,
            mediaId: item.id,
            mediaCategory: item.category,
            mediaPoster: item.poster,
            episode: item.episode,
            season: item.season,
          ),
        ),
      );
    } else {
      _openDetail(AnimeModel(
        id: item.mediaId.isNotEmpty ? item.mediaId : item.id.replaceAll(RegExp(r'^anime:|:ep:\d+$'), ''),
        name: item.title,
        poster: item.poster,
        background: item.poster,
        description: '',
      ));
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowFav ? 'Đã thêm vào Yêu thích' : 'Đã xóa khỏi Yêu thích'),
            backgroundColor: nowFav ? const Color(0xFFE50914) : Colors.grey[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else if (action == MovieAction.removeHistory) {
      WatchHistoryService.instance.clearProgress(item.id);
    }
  }

  void _openAnimeCardMenu(AnimeModel anime) async {
    final favId = 'anime:${anime.id}';
    final isFav = FavoritesService.instance.isFavorite(favId);

    final action = await MovieActionDialog.show(
      context,
      title: anime.name,
      poster: anime.poster,
      isFavorite: isFav,
      hasHistory: false,
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nowFav ? 'Đã thêm vào Yêu thích' : 'Đã xóa khỏi Yêu thích'),
            backgroundColor: nowFav ? const Color(0xFFE50914) : Colors.grey[800],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSkeletonLoading();
    }

    if (_errorMessage != null && _catalogData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFE50914), size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                ),
                onPressed: _loadAllData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử Lại'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HERO BILLBOARD BANNER
            if (_featuredList.isNotEmpty) _buildBillboardSlider(),

            const SizedBox(height: 16),

            // 2. CONTINUE WATCHING (▶ TIẾP TỤC XEM)
            if (_continueWatching.isNotEmpty) ...[
              _buildSectionHeader('▶ TIẾP TỤC XEM ANIME & PHIM', badge: 'LỊCH SỬ'),
              _buildContinueWatchingRow(),
              const SizedBox(height: 24),
            ],

            // 3. MY FAVORITES (❤️ DANH SÁCH YÊU THÍCH)
            if (_favorites.isNotEmpty) ...[
              _buildSectionHeader('❤️ DANH SÁCH YÊU THÍCH CỦA BẠN', badge: 'YÊU THÍCH'),
              _buildAnimePosterRow(_favorites),
              const SizedBox(height: 24),
            ],

            // 4. CATEGORY ROWS (MỖI FILTER 1 DÒNG DANH MỤC)
            for (final cat in _categories) ...[
              if ((_catalogData[cat['id']!] ?? []).isNotEmpty) ...[
                _buildSectionHeader(cat['title']!, badge: cat['badge']),
                _buildAnimePosterRow(_catalogData[cat['id']!]!),
                const SizedBox(height: 24),
              ],
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // HERO BILLBOARD BANNER
  // =========================================================================
  Widget _buildBillboardSlider() {
    if (_featuredList.isEmpty) return const SizedBox.shrink();

    return Focus(
      onFocusChange: (hasFocus) {
        setState(() {
          _isBannerInteracting = hasFocus;
        });
      },
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            _isBannerInteracting = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isBannerInteracting = false;
          });
        },
        child: SizedBox(
          height: 330,
          width: double.infinity,
          child: Stack(
            children: [
              PageView.builder(
                controller: _bannerPageController,
                itemCount: _featuredList.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentBannerIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final anime = _featuredList[index];
                  return _buildBillboardItem(anime, isCurrent: index == _currentBannerIndex);
                },
              ),

              // Left Arrow (Hover / Mouse navigation)
              if (_featuredList.length > 1)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isBannerInteracting ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_isBannerInteracting,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.55),
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                          onPressed: () {
                            final prevIndex = (_currentBannerIndex - 1 + _featuredList.length) % _featuredList.length;
                            _bannerPageController.animateToPage(
                              prevIndex,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

              // Right Arrow (Hover / Mouse navigation)
              if (_featuredList.length > 1)
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isBannerInteracting ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_isBannerInteracting,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.55),
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.arrow_forward_ios_rounded, size: 20),
                          onPressed: () {
                            final nextIndex = (_currentBannerIndex + 1) % _featuredList.length;
                            _bannerPageController.animateToPage(
                              nextIndex,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),

              // Slide Indicator Dots
              if (_featuredList.length > 1)
                Positioned(
                  bottom: 16,
                  right: 32,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(_featuredList.length, (i) {
                      final isActive = i == _currentBannerIndex;
                      return GestureDetector(
                        onTap: () {
                          _bannerPageController.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isActive ? 24 : 8,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0xFFE50914) : Colors.white.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillboardItem(AnimeModel anime, {required bool isCurrent}) {
    final bgUrl = anime.background.isNotEmpty ? anime.background : anime.poster;
    final favId = 'anime:${anime.id}';
    final isFav = FavoritesService.instance.isFavorite(favId);

    return Container(
      height: 330,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Backdrop Image
          if (bgUrl.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: bgUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: 1080,
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),

          // Vignette Gradient Left-to-Right
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0F0F0F),
                  Color(0xE60F0F0F),
                  Color(0x990F0F0F),
                  Colors.transparent,
                ],
                stops: [0.0, 0.45, 0.75, 1.0],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),

          // Vignette Gradient Bottom-to-Top
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F0F0F), Colors.transparent],
                stops: [0.0, 0.75],
                begin: Alignment.bottomCenter,
                end: Alignment.center,
              ),
            ),
          ),

          // Top subtle shade
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0x80000000), Colors.transparent],
                stops: [0.0, 0.3],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // Billboard Content
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ANIME YUMEI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'FULL HD • THUYẾT MINH & LỒNG TIẾNG',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Title
                Text(
                  anime.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.15,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Description
                if (anime.description.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Text(
                      anime.description,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 12,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else
                  const SizedBox(height: 12),

                // Action Buttons
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
                      // Button 1: Xem Ngay
                      TvFocusableCard(
                        focusNode: isCurrent ? _billboardPlayFocusNode : null,
                        onFocusChange: (hasFocus) {
                          if (hasFocus) _scrollToTopOnBillboardFocus();
                        },
                        onTap: () => _openDetail(anime),
                        borderRadius: BorderRadius.circular(6),
                        scale: 1.08,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withOpacity(0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'Xem Ngay',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Button 2: Thông tin chi tiết
                      TvFocusableCard(
                        onFocusChange: (hasFocus) {
                          if (hasFocus) _scrollToTopOnBillboardFocus();
                        },
                        onTap: () => _openDetail(anime),
                        borderRadius: BorderRadius.circular(6),
                        scale: 1.08,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Chi Tiết',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Button 3: Yêu Thích
                      TvFocusableCard(
                        onFocusChange: (hasFocus) {
                          if (hasFocus) _scrollToTopOnBillboardFocus();
                        },
                        onTap: () {
                          final nowFav = FavoritesService.instance.toggleFavorite(
                            FavoriteItem(
                              id: favId,
                              title: anime.name,
                              poster: anime.poster,
                              category: 'anime',
                              createdAt: DateTime.now().toIso8601String(),
                            ),
                          );
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(nowFav ? 'Đã thêm vào Yêu thích' : 'Đã xóa khỏi Yêu thích'),
                              backgroundColor: nowFav ? const Color(0xFFE50914) : Colors.grey[800],
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        scale: 1.08,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? const Color(0xFFE50914) : Colors.white,
                            size: 18,
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
  // SECTION HEADER
  // =========================================================================
  Widget _buildSectionHeader(String title, {String? badge}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // CONTINUE WATCHING HORIZONTAL ROW (16:9 Thumbnail + Progress Bar)
  // =========================================================================
  Widget _buildContinueWatchingRow() {
    return NetflixScrollableRow(
      height: 165,
      itemCount: _continueWatching.length,
      itemSpacing: 14,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      itemBuilder: (context, idx) {
        final item = _continueWatching[idx];
        return RepaintBoundary(
          child: TvFocusableCard(
            onTap: () => _playContinueWatching(item),
            onLongPress: () => _openContinueWatchingMenu(item),
            borderRadius: BorderRadius.circular(8),
            scale: 1.05,
            focusBorderColor: Colors.white,
            child: Container(
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 16:9 Thumbnail
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          child: CachedNetworkImage(
                            imageUrl: item.poster,
                            fit: BoxFit.cover,
                            memCacheWidth: 440,
                            placeholder: (_, __) => Container(color: const Color(0xFF202020)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF202020),
                              child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 28),
                            ),
                          ),
                        ),

                        // Vignette
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, Color(0x99000000)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),

                        // Episode Badge
                        if (item.episode != null && item.episode! > 0)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'TẬP ${item.episode}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Center Play Icon
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.65),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                          ),
                        ),

                        // Red Progress Bar
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

                  // Title & Duration
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.formattedPosition} / ${item.formattedDuration}',
                          style: const TextStyle(
                            color: Color(0xFFE50914),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
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
    );
  }

  // =========================================================================
  // ANIME POSTER ROW (2:3 Vertical Movie Poster Style)
  // =========================================================================
  Widget _buildAnimePosterRow(List<AnimeModel> items) {
    return NetflixScrollableRow(
      height: 235,
      itemCount: items.length,
      itemSpacing: 12,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      itemBuilder: (context, idx) {
        final anime = items[idx];
        return RepaintBoundary(
          child: TvFocusableCard(
            onTap: () => _openDetail(anime),
            onLongPress: () => _openAnimeCardMenu(anime),
            borderRadius: BorderRadius.circular(8),
            scale: 1.06,
            focusBorderColor: Colors.white,
            child: SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vertical Poster 2:3
                  Container(
                    height: 185,
                    width: 130,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: CachedNetworkImage(
                            imageUrl: anime.poster,
                            fit: BoxFit.cover,
                            memCacheWidth: 260,
                            memCacheHeight: 390,
                            placeholder: (_, __) => Container(
                              color: const Color(0xFF1E1E1E),
                              child: const Center(
                                child: Icon(Icons.auto_awesome, color: Colors.white10, size: 24),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF1E1E1E),
                              child: const Center(
                                child: Icon(Icons.broken_image_rounded, color: Colors.white24, size: 24),
                              ),
                            ),
                          ),
                        ),

                        // Bottom subtle shadow inside poster
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
                              gradient: LinearGradient(
                                colors: [Colors.transparent, Colors.black.withOpacity(0.65)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Title below poster
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      anime.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                        height: 1.25,
                      ),
                      maxLines: 2,
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

  // =========================================================================
  // SKELETON LOADING
  // =========================================================================
  Widget _buildSkeletonLoading() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Billboard skeleton
            Container(
              height: 320,
              width: double.infinity,
              color: const Color(0xFF181818),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
            ),
            const SizedBox(height: 24),

            // Rows skeleton
            for (int i = 0; i < 3; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                child: Container(
                  width: 180,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF202020),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              SizedBox(
                height: 235,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 6,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, __) => Container(
                    width: 130,
                    height: 185,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}
