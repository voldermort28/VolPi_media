import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/telegram_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class TelegramScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isActive;

  const TelegramScreen({
    super.key,
    required this.apiService,
    this.isActive = false,
  });

  @override
  TelegramScreenState createState() => TelegramScreenState();
}

class TelegramScreenState extends State<TelegramScreen> {
  List<TelegramSourceModel> _sources = [];
  TelegramSourceModel? _selectedSource;
  bool _isLoading = true;
  String? _errorMessage;

  List<TelegramVideoModel> _videos = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final FocusNode _sourceButtonFocusNode = FocusNode(debugLabel: 'TelegramSourceButton');
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'TelegramFirstCard');

  FocusNode get firstCardFocusNode => _firstCardFocusNode;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _sourceButtonFocusNode.dispose();
    _firstCardFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    await _loadSources(forceRefresh: true);
  }

  Future<void> _loadSources({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final sources = await widget.apiService.getTelegramSources(forceRefresh: forceRefresh);
      if (!mounted) return;

      setState(() {
        _sources = sources;
        _isLoading = false;
      });

      if (sources.isNotEmpty) {
        final prevId = _selectedSource?.id;
        final matching = sources.firstWhere(
          (s) => s.id == prevId,
          orElse: () => sources.first,
        );
        _selectSource(matching, forceRefresh: forceRefresh);
      } else {
        setState(() {
          _selectedSource = null;
          _videos = [];
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Không thể tải danh sách kênh Telegram: $e';
      });
    }
  }

  void _selectSource(TelegramSourceModel source, {bool forceRefresh = false}) {
    setState(() {
      _selectedSource = source;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadVideos(source.channelId, forceRefresh: forceRefresh);
  }

  Future<void> _loadVideos(String channelId, {bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.apiService.getTelegramVideos(channelId, forceRefresh: forceRefresh);
      if (!mounted) return;

      if (result != null) {
        setState(() {
          _videos = result.videos;
          _isLoading = false;
        });
      } else {
        setState(() {
          _videos = [];
          _isLoading = false;
          _errorMessage = 'Không có video nào trong kênh này hoặc tài khoản chưa có quyền truy cập.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Lỗi truy cập kênh Telegram: $e';
      });
    }
  }

  void _playVideo(TelegramVideoModel video) {
    final streamUrl = widget.apiService.getTelegramStreamUrl(video.channelId, video.id);
    final posterUrl = video.thumbnailUrl != null
        ? '${widget.apiService.baseUrl}${video.thumbnailUrl}'
        : '';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: streamUrl,
          title: video.title,
          subtitle: _selectedSource?.name ?? 'Telegram Phim',
          mediaId: 'telegram_${video.channelId}_${video.id}',
          mediaCategory: 'telegram',
          mediaPoster: posterUrl,
        ),
      ),
    );
  }

  void _showSourceSelectionDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF262626)),
        ),
        title: const Row(
          children: [
            Icon(Icons.send_rounded, color: Color(0xFF38BDF8), size: 22),
            SizedBox(width: 10),
            Text(
              'Chọn Kênh Phim Telegram',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: _sources.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Chưa có kênh Telegram nào được thêm.\nVui lòng vào website quản trị để thêm kênh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _sources.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final source = _sources[index];
                    final isSelected = _selectedSource?.id == source.id;

                    return TvFocusableCard(
                      onTap: () {
                        Navigator.of(dialogCtx).pop();
                        if (!isSelected) {
                          _selectSource(source);
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF0284C7).withOpacity(0.25) : const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF38BDF8) : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.send_rounded,
                              size: 18,
                              color: Color(0xFF38BDF8),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    source.name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    source.channelId,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF38BDF8), size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF262626))),
      ),
      child: Row(
        children: [
          // Kênh Dropdown Selector Button (giống IPTV & GDrive)
          TvFocusableCard(
            focusNode: _sourceButtonFocusNode,
            onTap: _showSourceSelectionDialog,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2642),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.send_rounded, size: 18, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      _selectedSource?.name ?? 'Chọn Kênh Telegram',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 22),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Search Field
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E2E2E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: const InputDecoration(
                        hintText: 'Tìm kiếm phim trong kênh này...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val.trim().toLowerCase();
                        });
                      },
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                      child: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 20),
            tooltip: 'Làm mới',
            onPressed: () {
              if (_selectedSource != null) {
                _loadVideos(_selectedSource!.channelId, forceRefresh: true);
              } else {
                _loadSources(forceRefresh: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF38BDF8)),
            SizedBox(height: 12),
            Text('Đang quét video từ kênh Telegram...', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadSources(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Thử Lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_sources.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_and_archive_rounded, color: Colors.white38, size: 56),
              const SizedBox(height: 14),
              const Text(
                'Chưa Có Kênh Telegram Nào Được Thêm',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vui lòng mở trang web quản trị của server để dán link kênh Telegram:\nhttps://stremio.laboon.vn/telegram',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _loadSources(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Quét Lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filteredVideos = _videos.where((v) {
      if (_searchQuery.isEmpty) return true;
      return v.title.toLowerCase().contains(_searchQuery) ||
          v.fileName.toLowerCase().contains(_searchQuery) ||
          v.caption.toLowerCase().contains(_searchQuery);
    }).toList();

    if (filteredVideos.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'Không tìm thấy kết quả phù hợp cho "$_searchQuery"' : 'Kênh này hiện chưa có video nào.',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: filteredVideos.length,
      itemBuilder: (ctx, index) {
        final video = filteredVideos[index];
        final isFirst = index == 0;
        return _buildMovieCard(video, isFirst: isFirst);
      },
    );
  }

  Widget _buildMovieCard(TelegramVideoModel video, {bool isFirst = false}) {
    final posterUrl = video.thumbnailUrl != null
        ? '${widget.apiService.baseUrl}${video.thumbnailUrl}'
        : null;

    return TvFocusableCard(
      focusNode: isFirst ? _firstCardFocusNode : null,
      onTap: () => _playVideo(video),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF282828)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFF0A0A0A),
                    width: double.infinity,
                    child: posterUrl != null
                        ? CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Center(
                              child: Icon(Icons.play_circle_fill_rounded, color: Color(0xFF38BDF8), size: 38),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.play_circle_fill_rounded, color: Color(0xFF38BDF8), size: 38),
                          ),
                  ),
                ),

                // Title & Details
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              video.formattedSize,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (video.formattedDuration.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.35), width: 0.8),
                                ),
                                child: Text(
                                  video.formattedDuration,
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
