import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/gdrive_model.dart';
import '../services/audio_player_handler.dart';
import '../widgets/tv_focusable_card.dart';
import '../widgets/music_player_bottom_sheet.dart';
import '../player/video_player_screen.dart';

class MusicScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isActive;

  const MusicScreen({
    super.key,
    required this.apiService,
    this.isActive = false,
  });

  @override
  MusicScreenState createState() => MusicScreenState();
}

class MusicScreenState extends State<MusicScreen> {
  // 0: Nghe Nhạc, 1: Video & Phim
  int _mediaSubTab = 0;

  List<GDriveSourceModel> _sources = [];
  GDriveSourceModel? _selectedSource;
  bool _isLoading = true;
  String? _errorMessage;

  // Breadcrumbs: each item is {'id': folderId, 'name': folderName}
  final List<Map<String, String>> _breadcrumbs = [];

  List<GDriveItemModel> _folders = [];
  List<GDriveItemModel> _tracks = [];
  List<GDriveItemModel> _videos = [];
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final FocusNode _firstCardFocusNode = FocusNode(debugLabel: 'MusicFirstCard');
  FocusNode get firstCardFocusNode => _firstCardFocusNode;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
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
      // Chỉ lấy các nguồn Google Drive CÔNG KHAI (isPrivate: false)
      final allSources = await widget.apiService.getGDriveSources(isPrivate: false, forceRefresh: forceRefresh);
      if (!mounted) return;

      setState(() {
        _sources = allSources;
        _isLoading = false;
      });

      if (allSources.isNotEmpty) {
        _autoSelectSourceForSubTab(forceRefresh: forceRefresh);
      } else {
        setState(() {
          _selectedSource = null;
          _folders = [];
          _tracks = [];
          _videos = [];
          _breadcrumbs.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Không thể tải nguồn media: $e';
      });
    }
  }

  void _autoSelectSourceForSubTab({bool forceRefresh = false}) {
    if (_sources.isEmpty) return;

    if (_mediaSubTab == 0) {
      // Nhạc: Ưu tiên chọn nguồn có chữ 'music' hoặc 'nhạc'
      final musicSource = _sources.firstWhere(
        (s) => s.name.toLowerCase().contains('music') || s.name.toLowerCase().contains('nhạc'),
        orElse: () => _sources.first,
      );
      _selectSource(musicSource, forceRefresh: forceRefresh);
    } else {
      // Video: Ưu tiên chọn nguồn có chữ 'phim' hoặc 'video' hoặc 'movie'
      final videoSource = _sources.firstWhere(
        (s) => s.name.toLowerCase().contains('phim') || s.name.toLowerCase().contains('video') || s.name.toLowerCase().contains('movie'),
        orElse: () => _sources.firstWhere(
          (s) => !s.name.toLowerCase().contains('music') && !s.name.toLowerCase().contains('nhạc'),
          orElse: () => _sources.first,
        ),
      );
      _selectSource(videoSource, forceRefresh: forceRefresh);
    }
  }

  void _setSubTab(int tab) {
    if (_mediaSubTab == tab) return;
    setState(() {
      _mediaSubTab = tab;
      _searchQuery = '';
      _searchController.clear();
    });
    _autoSelectSourceForSubTab();
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
          _tracks = result.audios;
          _videos = result.videos;
          _isLoading = false;
        });
      } else {
        setState(() {
          _folders = [];
          _tracks = [];
          _videos = [];
          _isLoading = false;
          _errorMessage = 'Thư mục trống hoặc không thể tải dữ liệu.';
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
      return true;
    }
    return false;
  }

  void _playTrack(GDriveItemModel track, List<GDriveItemModel> trackList) {
    final targetIndex = trackList.indexWhere((t) => t.id == track.id);
    if (targetIndex == -1) return;

    final currentAlbum = _breadcrumbs.isNotEmpty ? _breadcrumbs.last['name'] ?? 'Album' : 'Album';

    // Tạo danh sách MediaItem cho toàn bộ trackList này
    final mediaItems = trackList.map((t) {
      final streamUrl = widget.apiService.getGDriveStreamUrl(t.id);
      return MediaItem(
        id: streamUrl,
        title: t.name,
        album: currentAlbum,
        artist: t.folderName ?? _selectedSource?.name ?? 'VolPi Music',
        artUri: (t.thumbnailUrl != null && t.thumbnailUrl!.isNotEmpty) ? Uri.parse(t.thumbnailUrl!) : null,
      );
    }).toList();

    VolPiAudioHandler.instance.setPlaylist(mediaItems, initialIndex: targetIndex);
  }

  void _playAll() {
    if (_tracks.isNotEmpty) {
      _playTrack(_tracks[0], _tracks);
    }
  }

  void _playVideo(GDriveItemModel video) {
    final streamUrl = widget.apiService.getGDriveStreamUrl(video.id);
    final currentIndex = _videos.indexWhere((v) => v.id == video.id);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: streamUrl,
          title: video.name,
          subtitle: _selectedSource?.name ?? 'Google Drive Video',
          mediaId: 'gdrive_${video.id}',
          mediaCategory: 'gdrive',
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
    final bool isVideoMode = _mediaSubTab == 1;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF262626)),
        ),
        title: Row(
          children: [
            Icon(
              isVideoMode ? Icons.video_collection_rounded : Icons.library_music_rounded,
              color: isVideoMode ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              isVideoMode ? 'Chọn Nguồn Video Google Drive' : 'Chọn Nguồn Nhạc Google Drive',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: _sources.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Chưa có nguồn công khai nào.\nVui lòng vào website quản trị https://stremio.laboon.vn/gdrive để tick chọn "Đây là nguồn công khai".',
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
                    final isSelected = source.id == _selectedSource?.id;
                    final activeColor = isVideoMode ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8);

                    return InkWell(
                      onTap: () {
                        Navigator.of(dialogCtx).pop();
                        _selectSource(source);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? activeColor.withOpacity(0.2) : const Color(0xFF1F1F1F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? activeColor : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isVideoMode ? Icons.folder_video : Icons.album_rounded,
                              size: 20,
                              color: isSelected ? activeColor : Colors.white70,
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
                                  ),
                                  if (source.count > 0)
                                    Text(
                                      '${source.count} tập tin',
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected) Icon(Icons.check_circle_rounded, color: activeColor, size: 18),
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
        backgroundColor: const Color(0xFF0B132B),
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              _buildBreadcrumbBar(),
              Expanded(child: _buildBody()),
              _buildMiniPlayer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final activeThemeColor = _mediaSubTab == 0 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: [
          // 1. Segmented Switcher: [ 🎵 Nghe Nhạc | 🎬 Video & Phim ]
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            padding: const EdgeInsets.all(2.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentButton(
                  index: 0,
                  label: 'Nghe Nhạc',
                  icon: Icons.music_note_rounded,
                  activeColor: const Color(0xFF0284C7),
                ),
                const SizedBox(width: 3),
                _buildSegmentButton(
                  index: 1,
                  label: 'Video & Phim',
                  icon: Icons.video_library_rounded,
                  activeColor: const Color(0xFFD97706),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // 2. Nguồn Dropdown Button
          TvFocusableCard(
            onTap: _showSourceSelectionDialog,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: activeThemeColor.withOpacity(0.5), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _mediaSubTab == 0 ? Icons.library_music_rounded : Icons.video_collection_rounded,
                    size: 18,
                    color: activeThemeColor,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      _selectedSource?.name ?? 'Chọn Nguồn',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 20),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // 3. Search Field
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: _mediaSubTab == 0 ? 'Tìm bài hát hoặc album...' : 'Tìm video hoặc phim...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
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

          const SizedBox(width: 8),

          // 4. Refresh Button
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: activeThemeColor, size: 20),
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

  Widget _buildSegmentButton({
    required int index,
    required String label,
    required IconData icon,
    required Color activeColor,
  }) {
    final bool isSelected = _mediaSubTab == index;

    return TvFocusableCard(
      onTap: () => _setSubTab(index),
      borderRadius: BorderRadius.circular(8),
      focusBorderColor: activeColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbBar() {
    if (_breadcrumbs.isEmpty) return const SizedBox.shrink();
    final activeThemeColor = _mediaSubTab == 0 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0F172A),
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
                child: Row(
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 14, color: activeThemeColor),
                    const SizedBox(width: 4),
                    Text('Lùi lại', style: TextStyle(color: activeThemeColor, fontSize: 11, fontWeight: FontWeight.bold)),
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
                            color: isLast ? Colors.white : activeThemeColor,
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

          if (_mediaSubTab == 0 && _tracks.isNotEmpty)
            ElevatedButton.icon(
              onPressed: _playAll,
              icon: const Icon(Icons.play_circle_fill_rounded, size: 16),
              label: const Text('Phát Tất Cả'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _mediaSubTab == 0 ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 12),
            Text(
              _mediaSubTab == 0 ? 'Đang nạp danh sách nhạc...' : 'Đang nạp danh sách video...',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
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
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _loadSources(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Thử Lại'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    final filteredFolders = _folders.where((f) {
      if (_searchQuery.isEmpty) return true;
      return f.name.toLowerCase().contains(_searchQuery);
    }).toList();

    final filteredTracks = _tracks.where((t) {
      if (_searchQuery.isEmpty) return true;
      return t.name.toLowerCase().contains(_searchQuery);
    }).toList();

    final filteredVideos = _videos.where((v) {
      if (_searchQuery.isEmpty) return true;
      return v.name.toLowerCase().contains(_searchQuery);
    }).toList();

    if (_mediaSubTab == 0) {
      // -------------------------------------------------------------
      // SUB-TAB 0: NGHE NHẠC (ALBUM, BÀI HÁT & VIDEO MV)
      // -------------------------------------------------------------
      if (filteredFolders.isEmpty && filteredTracks.isEmpty && filteredVideos.isEmpty) {
        return const Center(
          child: Text('Thư mục này không có tập tin nhạc nào.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        );
      }

      return CustomScrollView(
        slivers: [
          // 1. Folders / Albums Section
          if (filteredFolders.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.folder_special_rounded, color: Color(0xFFF59E0B), size: 18),
                    SizedBox(width: 8),
                    Text('ALBUM & THƯ MỤC NHẠC', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  childAspectRatio: 0.88,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final folder = filteredFolders[idx];
                    return _buildFolderCard(folder, isFirst: idx == 0);
                  },
                  childCount: filteredFolders.length,
                ),
              ),
            ),
          ],

          // 2. Audio Tracks Section
          if (filteredTracks.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.music_note_rounded, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Text('DANH SÁCH BÀI HÁT', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final track = filteredTracks[idx];
                    return _buildTrackListItem(track, idx, filteredTracks);
                  },
                  childCount: filteredTracks.length,
                ),
              ),
            ),
          ],

          // 3. Video MV Section in Music Folder (if any)
          if (filteredVideos.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.video_collection_rounded, color: Color(0xFFF59E0B), size: 18),
                    SizedBox(width: 8),
                    Text('VIDEO & MV TRONG THƯ MỤC NÀY', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: 1.15,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final video = filteredVideos[idx];
                    return _buildVideoCard(video);
                  },
                  childCount: filteredVideos.length,
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 85)),
        ],
      );
    } else {
      // -------------------------------------------------------------
      // SUB-TAB 1: KHO VIDEO & PHIM (DUYỆT FOLDER PHIM, DANH SÁCH VIDEO)
      // -------------------------------------------------------------
      if (filteredFolders.isEmpty && filteredVideos.isEmpty) {
        return const Center(
          child: Text('Thư mục này không có tập tin video nào.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        );
      }

      return CustomScrollView(
        slivers: [
          // 1. Video Folders Section
          if (filteredFolders.isNotEmpty) ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.folder_special_rounded, color: Color(0xFFF59E0B), size: 18),
                    SizedBox(width: 8),
                    Text('THƯ MỤC PHIM & VIDEO', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  childAspectRatio: 0.88,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final folder = filteredFolders[idx];
                    return _buildFolderCard(folder, isFirst: idx == 0);
                  },
                  childCount: filteredFolders.length,
                ),
              ),
            ),
          ],

          // 2. Video Grid Section
          if (filteredVideos.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.movie_rounded, color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'DANH SÁCH VIDEO & PHIM (${filteredVideos.length})',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  childAspectRatio: 1.15,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final video = filteredVideos[idx];
                    return _buildVideoCard(video);
                  },
                  childCount: filteredVideos.length,
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 85)),
        ],
      );
    }
  }

  Widget _buildFolderCard(GDriveItemModel folder, {bool isFirst = false}) {
    final activeThemeColor = _mediaSubTab == 0 ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8);

    return TvFocusableCard(
      focusNode: isFirst ? _firstCardFocusNode : null,
      onTap: () => _navigateToSubfolder(folder),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: activeThemeColor.withOpacity(0.35)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: activeThemeColor.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_rounded, color: activeThemeColor, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              folder.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(4)),
              child: Text('Thư mục', style: TextStyle(color: activeThemeColor, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(GDriveItemModel video) {
    return TvFocusableCard(
      onTap: () => _playVideo(video),
      borderRadius: BorderRadius.circular(12),
      focusBorderColor: const Color(0xFFF59E0B),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B).withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail / Poster with play overlay
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  video.thumbnailUrl != null && video.thumbnailUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: video.thumbnailUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: const Color(0xFF0F172A)),
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF0F172A),
                            child: const Center(
                              child: Icon(Icons.movie_rounded, color: Colors.white30, size: 36),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF0F172A),
                          child: const Center(
                            child: Icon(Icons.movie_rounded, color: Colors.white30, size: 36),
                          ),
                        ),
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        video.formattedSize,
                        style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Video title
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                video.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackListItem(GDriveItemModel track, int index, List<GDriveItemModel> currentList) {
    final name = track.name;
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : 'AUDIO';
    final streamUrl = widget.apiService.getGDriveStreamUrl(track.id);
    final handler = VolPiAudioHandler.instance;

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnap) {
        final currentMedia = mediaSnap.data;
        final bool isCurrent = currentMedia != null && currentMedia.id == streamUrl;

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnap) {
            final state = stateSnap.data;
            final isPlaying = isCurrent && (state?.playing ?? false);
            final isBuffering = isCurrent &&
                (state?.processingState == AudioProcessingState.buffering ||
                    state?.processingState == AudioProcessingState.loading);

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: TvFocusableCard(
                onTap: () {
                  if (isCurrent) {
                    if (isPlaying) {
                      handler.pause();
                    } else {
                      handler.play();
                    }
                  } else {
                    _playTrack(track, currentList);
                  }
                },
                borderRadius: BorderRadius.circular(10),
                focusBorderColor: const Color(0xFF38BDF8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent ? const Color(0xFF0284C7).withOpacity(0.22) : const Color(0xFF1E293B).withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCurrent ? const Color(0xFF38BDF8).withOpacity(0.8) : Colors.white.withOpacity(0.06),
                      width: isCurrent ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Track Number Badge / Equalizer / Loading Spinner
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrent ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Center(
                          child: isBuffering
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : (isPlaying
                                  ? const Icon(Icons.equalizer_rounded, color: Colors.white, size: 18)
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: isCurrent ? Colors.white : const Color(0xFF38BDF8),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    )),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Title and Size
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFF38BDF8) : Colors.white,
                                fontSize: 13,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  track.formattedSize,
                                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: ext == 'FLAC' ? const Color(0xFF0284C7).withOpacity(0.2) : Colors.white10,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    ext,
                                    style: TextStyle(
                                      color: ext == 'FLAC' ? const Color(0xFF38BDF8) : Colors.white60,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Action Status Icon
                      Icon(
                        isBuffering
                            ? Icons.hourglass_top_rounded
                            : (isPlaying
                                ? Icons.pause_circle_filled_rounded
                                : (isCurrent ? Icons.play_circle_filled_rounded : Icons.play_circle_outline_rounded)),
                        color: const Color(0xFF38BDF8),
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniPlayer() {
    final handler = VolPiAudioHandler.instance;

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        if (item == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data;
            final playing = state?.playing ?? false;
            final pos = state?.position ?? Duration.zero;
            final buffered = state?.bufferedPosition ?? Duration.zero;
            final dur = item.duration ?? Duration.zero;
            final isBuffering = state?.processingState == AudioProcessingState.buffering ||
                state?.processingState == AudioProcessingState.loading;

            return GestureDetector(
              onTap: () => MusicPlayerBottomSheet.show(context),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  border: Border(top: BorderSide(color: Color(0xFF0284C7), width: 1.5)),
                  boxShadow: [
                    BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, -2)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dual-Layer Thin Buffer & Progress Bar at Top
                    if (dur.inMilliseconds > 0)
                      SizedBox(
                        height: 2.5,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            Container(color: const Color(0xFF1E293B)),
                            // Buffer Bar
                            FractionallySizedBox(
                              widthFactor: (buffered.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0),
                              child: Container(color: const Color(0xFF38BDF8).withOpacity(0.35)),
                            ),
                            // Position Bar
                            FractionallySizedBox(
                              widthFactor: (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0),
                              child: Container(color: const Color(0xFF38BDF8)),
                            ),
                          ],
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          // Mini Thumbnail
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: item.artUri != null
                                ? CachedNetworkImage(imageUrl: item.artUri.toString(), fit: BoxFit.cover)
                                : const Icon(Icons.music_note_rounded, color: Color(0xFF38BDF8), size: 24),
                          ),

                          const SizedBox(width: 12),

                          // Title & Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.artist ?? item.album ?? 'VolPi Music',
                                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (dur.inMilliseconds > 0 && buffered.inMilliseconds > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        'Buffer: ${((buffered.inMilliseconds / dur.inMilliseconds) * 100).clamp(0, 100).toInt()}%',
                                        style: TextStyle(
                                          color: const Color(0xFF38BDF8).withOpacity(0.75),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Mini Controls
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70, size: 24),
                            onPressed: () => handler.skipToPrevious(),
                          ),
                          IconButton(
                            icon: isBuffering
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
                                    ),
                                  )
                                : Icon(
                                    playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                                    color: const Color(0xFF38BDF8),
                                    size: 32,
                                  ),
                            onPressed: () => playing ? handler.pause() : handler.play(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 24),
                            onPressed: () => handler.skipToNext(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
