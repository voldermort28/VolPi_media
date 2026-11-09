import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/gdrive_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class GDriveScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isActive;

  const GDriveScreen({
    super.key,
    required this.apiService,
    this.isActive = false,
  });

  @override
  GDriveScreenState createState() => GDriveScreenState();
}

class GDriveScreenState extends State<GDriveScreen> {
  List<GDriveSourceModel> _sources = [];
  GDriveSourceModel? _selectedSource;
  bool _isLoading = true;
  String? _errorMessage;

  // Breadcrumb navigation stack: each entry is {'id': folderId, 'name': folderName}
  final List<Map<String, String>> _breadcrumbs = [];

  List<GDriveItemModel> _folders = [];
  List<GDriveItemModel> _videos = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final FocusNode _sourceButtonFocusNode = FocusNode(debugLabel: 'GDriveSourceButton');
  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'GDriveFirstCard');

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
      final sources = await widget.apiService.getGDriveSources(forceRefresh: forceRefresh);
      if (!mounted) return;

      setState(() {
        _sources = sources;
        _isLoading = false;
      });

      if (sources.isNotEmpty) {
        // Select first source or retain previous if still valid
        final prevId = _selectedSource?.id;
        final matching = sources.firstWhere(
          (s) => s.id == prevId,
          orElse: () => sources.first,
        );
        _selectSource(matching, forceRefresh: forceRefresh);
      } else {
        setState(() {
          _selectedSource = null;
          _folders = [];
          _videos = [];
          _breadcrumbs.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Không thể tải danh sách nguồn Google Drive: $e';
      });
    }
  }

  void _selectSource(GDriveSourceModel source, {bool forceRefresh = false}) {
    setState(() {
      _selectedSource = source;
      _breadcrumbs.clear();
      _breadcrumbs.add({'id': source.folderId, 'name': source.name});
      _searchQuery = '';
      _searchController.clear();
    });
    _loadFolder(source.folderId, forceRefresh: forceRefresh);
  }

  Future<void> _loadFolder(String folderId, {bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.apiService.getGDriveFolderContents(folderId, forceRefresh: forceRefresh);
      if (!mounted) return;

      if (result != null) {
        setState(() {
          _folders = result.folders;
          _videos = result.videos;
          _isLoading = false;
        });
      } else {
        setState(() {
          _folders = [];
          _videos = [];
          _isLoading = false;
          _errorMessage = 'Không có tập tin nào trong thư mục này hoặc link không thể truy cập.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Lỗi truy cập thư mục: $e';
      });
    }
  }

  void _navigateToSubfolder(GDriveItemModel folder) {
    setState(() {
      _breadcrumbs.add({'id': folder.id, 'name': folder.name});
      _searchQuery = '';
      _searchController.clear();
    });
    _loadFolder(folder.id);
  }

  bool _navigateBack() {
    if (_breadcrumbs.length > 1) {
      setState(() {
        _breadcrumbs.removeLast();
        _searchQuery = '';
        _searchController.clear();
      });
      final current = _breadcrumbs.last;
      _loadFolder(current['id']!);
      return true; // Handled back
    }
    return false; // Reached root
  }

  void _playVideo(GDriveItemModel video) {
    final streamUrl = widget.apiService.getGDriveStreamUrl(video.id);
    final isPrivate = _selectedSource?.isPrivate ?? true;
    final currentIndex = _videos.indexWhere((v) => v.id == video.id);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: streamUrl,
          title: video.name,
          subtitle: _selectedSource?.name ?? 'Google Drive',
          mediaId: 'gdrive_${video.id}',
          mediaCategory: isPrivate ? 'secret' : 'gdrive',
          mediaPoster: video.thumbnailUrl ?? '',
          onNext: (currentIndex != -1 && currentIndex < _videos.length - 1)
              ? () {
                  Navigator.of(context).pop();
                  _playVideo(_videos[currentIndex + 1]);
                }
              : null,
          onPrevious: (currentIndex > 0)
              ? () {
                  Navigator.of(context).pop();
                  _playVideo(_videos[currentIndex - 1]);
                }
              : null,
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
            Icon(Icons.cloud_circle_rounded, color: Color(0xFF38BDF8), size: 24),
            SizedBox(width: 10),
            Text(
              'Chọn Nguồn Google Drive',
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
                    'Chưa có nguồn nào được cấu hình.\nVui lòng vào website quản trị để thêm nguồn.',
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
                            Icon(
                              source.isPrivate ? Icons.lock_rounded : Icons.folder_shared_rounded,
                              size: 20,
                              color: isSelected ? const Color(0xFF38BDF8) : Colors.white70,
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
                                    source.isPrivate ? 'Thư mục riêng tư' : 'Thư mục chia sẻ',
                                    style: TextStyle(
                                      color: source.isPrivate ? const Color(0xFF818CF8) : const Color(0xFF34D399),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
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
    return PopScope(
      canPop: _breadcrumbs.length <= 1,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _navigateBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),
              _buildBreadcrumbBar(),
              Expanded(
                child: _buildBody(),
              ),
            ],
          ),
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
          // Nguồn Dropdown Selector Button (giống IPTV)
          TvFocusableCard(
            focusNode: _sourceButtonFocusNode,
            onTap: _showSourceSelectionDialog,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.5), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_circle_rounded, size: 20, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      _selectedSource?.name ?? 'Chọn Nguồn Drive',
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
                        hintText: 'Tìm kiếm tập tin trong thư mục này...',
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
              if (_breadcrumbs.isNotEmpty) {
                _loadFolder(_breadcrumbs.last['id']!, forceRefresh: true);
              } else {
                _loadSources(forceRefresh: true);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbBar() {
    if (_breadcrumbs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF111827),
      child: Row(
        children: [
          if (_breadcrumbs.length > 1)
            InkWell(
              onTap: _navigateBack,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 14, color: Color(0xFF38BDF8)),
                    SizedBox(width: 4),
                    Text('Lùi lại', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_breadcrumbs.length, (idx) {
                  final crumb = _breadcrumbs[idx];
                  final isLast = idx == _breadcrumbs.length - 1;

                  return Row(
                    children: [
                      if (idx > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white38),
                        ),
                      GestureDetector(
                        onTap: isLast
                            ? null
                            : () {
                                setState(() {
                                  _breadcrumbs.removeRange(idx + 1, _breadcrumbs.length);
                                });
                                _loadFolder(crumb['id']!);
                              },
                        child: Text(
                          crumb['name']!,
                          style: TextStyle(
                            color: isLast ? Colors.white : const Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: isLast ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          if (!_isLoading) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Text(
                '${_videos.length} video' + (_folders.isNotEmpty ? ' • ${_folders.length} thư mục' : ''),
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
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
            Text('Đang nạp tập tin từ Google Drive...', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
              const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 56),
              const SizedBox(height: 14),
              const Text(
                'Chưa Có Nguồn Thư Mục Google Drive Nào',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Vui lòng mở trang web quản trị của server để dán link thư mục Google Drive:\nhttps://stremio.laboon.vn/gdrive',
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

    // Filter items
    final filteredFolders = _folders.where((f) {
      if (_searchQuery.isEmpty) return true;
      return f.name.toLowerCase().contains(_searchQuery);
    }).toList();

    final filteredVideos = _videos.where((v) {
      if (_searchQuery.isEmpty) return true;
      return v.name.toLowerCase().contains(_searchQuery);
    }).toList();

    if (filteredFolders.isEmpty && filteredVideos.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'Không tìm thấy kết quả phù hợp cho "$_searchQuery"' : 'Thư mục này hiện đang trống.',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    final totalCount = filteredFolders.length + filteredVideos.length;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.82,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: totalCount,
      itemBuilder: (ctx, index) {
        final isFolderItem = index < filteredFolders.length;
        final isFirst = index == 0;

        if (isFolderItem) {
          final folder = filteredFolders[index];
          return _buildFolderCard(folder, isFirst: isFirst);
        } else {
          final videoIndex = index - filteredFolders.length;
          final video = filteredVideos[videoIndex];
          return _buildVideoCard(video, isFirst: isFirst && filteredFolders.isEmpty);
        }
      },
    );
  }

  Widget _buildFolderCard(GDriveItemModel folder, {bool isFirst = false}) {
    return TvFocusableCard(
      focusNode: isFirst ? _firstCardFocusNode : null,
      onTap: () => _navigateToSubfolder(folder),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3), width: 1.0),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_rounded, color: Color(0xFFF59E0B), size: 30),
            ),
            const SizedBox(height: 10),
            Text(
              folder.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Thư mục',
                style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(GDriveItemModel video, {bool isFirst = false}) {
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
                // Thumbnail / Play Icon Header
                Expanded(
                  flex: 3,
                  child: Container(
                    color: const Color(0xFF0A0A0A),
                    width: double.infinity,
                    child: video.thumbnailUrl != null && video.thumbnailUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: video.thumbnailUrl!,
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

                // Title & Size Footer
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          video.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (video.folderName != null && video.folderName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open_rounded, size: 10, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    video.folderName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
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
                            if (video.subtitleFileId != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4), width: 0.8),
                                ),
                                child: const Text(
                                  'SUB',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 8,
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
