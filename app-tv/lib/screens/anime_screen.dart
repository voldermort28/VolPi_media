import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/anime_model.dart';
import '../widgets/tv_focusable_card.dart';
import 'anime_detail_screen.dart';

class AnimeScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback? onNavigateUp;
  final FocusNode? primaryFocusNode;

  const AnimeScreen({
    super.key,
    required this.apiService,
    this.onNavigateUp,
    this.primaryFocusNode,
  });

  @override
  State<AnimeScreen> createState() => _AnimeScreenState();
}

class _AnimeScreenState extends State<AnimeScreen> {
  final List<Map<String, String>> _categories = [
    {'id': 'yumei-top', 'name': '🌟 4 Thế Giới'},
    {'id': 'yumei-pokemon', 'name': '⚡ Pokemon'},
    {'id': 'yumei-sentai', 'name': '⚔️ Super Sentai'},
    {'id': 'yumei-power-rangers', 'name': '⚡ Power Rangers'},
    {'id': 'yumei-anime', 'name': '🌸 Anime khác'},
    {'id': 'yumei-movies', 'name': '🎬 Phim Lẻ Anime'},
  ];

  late final List<FocusNode> _categoryFocusNodes = List.generate(
    _categories.length,
    (_) => FocusNode(),
  );
  final FocusNode _firstGridCardFocusNode = FocusNode();

  int _selectedCategoryIndex = 0;
  List<AnimeModel> _items = [];
  bool _isLoading = true;
  final Map<String, List<AnimeModel>> _catalogCache = {};

  @override
  void initState() {
    super.initState();
    _loadCategory(0);
  }

  @override
  void dispose() {
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    _firstGridCardFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadCategory(int index) async {
    final catId = _categories[index]['id']!;

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

  @override
  Widget build(BuildContext context) {
    return Column(
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
              final focusNode = (idx == 0 && widget.primaryFocusNode != null)
                  ? widget.primaryFocusNode!
                  : _categoryFocusNodes[idx];

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TvFocusableCard(
                  focusNode: focusNode,
                  onTap: () => _loadCategory(idx),
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      // Press UP -> Jump to Top Nav Bar
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                        widget.onNavigateUp?.call();
                        return KeyEventResult.handled;
                      }
                      // Press DOWN -> Jump to first item of movie grid
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        if (_items.isNotEmpty) {
                          _firstGridCardFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
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

        // Grid Content Area
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
              : _items.isEmpty
                  ? const Center(child: Text('Không có nội dung trong danh mục này.', style: TextStyle(color: Colors.white54)))
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
                            return _buildAnimeCard(anime, idx, crossAxisCount);
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildAnimeCard(AnimeModel anime, int idx, int crossAxisCount) {
    return TvFocusableCard(
      focusNode: idx == 0 ? _firstGridCardFocusNode : null,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
          // If on the first row of grid items, pressing UP jumps back to category pill
          if (idx < crossAxisCount) {
            final targetNode = (widget.primaryFocusNode != null && _selectedCategoryIndex == 0)
                ? widget.primaryFocusNode!
                : _categoryFocusNodes[_selectedCategoryIndex];
            targetNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      onTap: () => _openDetail(anime),
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
