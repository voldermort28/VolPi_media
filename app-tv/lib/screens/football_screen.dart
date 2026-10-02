import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_service.dart';
import '../models/match_model.dart';
import '../widgets/tv_focusable_card.dart';
import '../player/video_player_screen.dart';

class FootballScreen extends StatefulWidget {
  final ApiService apiService;

  const FootballScreen({super.key, required this.apiService});

  @override
  State<FootballScreen> createState() => _FootballScreenState();
}

class _FootballScreenState extends State<FootballScreen> {
  List<MatchModel> _matches = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMatches(forceRefresh: true);
  }

  Future<void> _loadMatches({bool forceRefresh = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await widget.apiService.getLiveMatches(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _matches = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Không thể tải lịch thi đấu: ${e.toString()}';
        });
      }
    }
  }

  void _onMatchSelected(MatchModel match) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF38BDF8)),
      ),
    );

    final streams = await widget.apiService.getMatchStreams(match.id);
    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading dialog

    if (streams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có luồng phát sóng cho trận này hoặc trận chưa diễn ra.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    if (streams.length == 1) {
      _playStream(match, streams[0], streams);
    } else {
      _showChannelSelector(match, streams);
    }
  }

  void _showChannelSelector(MatchModel match, List<StreamChannel> channels) {
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
                      '${match.homeTeam} vs ${match.awayTeam}',
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
                'Chọn kênh bình luận viên để xem trực tiếp:',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: channels.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final ch = channels[idx];
                    return TvFocusableCard(
                      autoFocus: idx == 0,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _playStream(match, ch, channels);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        color: const Color(0xFF1E293B),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_fill, color: Color(0xFF38BDF8), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                ch.title,
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
              ),
            ],
          ),
        );
      },
    );
  }

  void _playStream(MatchModel match, StreamChannel channel, List<StreamChannel> allChannels) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          streamUrl: channel.url,
          title: '${match.homeTeam} vs ${match.awayTeam}',
          subtitle: '${channel.title} • ${match.league}',
          headers: channel.headers,
          availableChannels: allChannels,
          isLive: true,
        ),
      ),
    );
  }

  List<MatchModel> get _majorMatches => _matches.where((m) => m.isFamous || m.isVietnam || m.isFavorite).toList();
  List<MatchModel> get _otherMatches => _matches.where((m) => !m.isFamous && !m.isVietnam && !m.isFavorite).toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Action Bar (Header with Refresh Button for TV Remote)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('⚽', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  const Text(
                    'Trực Tiếp Hôm Nay',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 10),
                  if (_matches.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                      ),
                      child: Text(
                        '${_matches.length} trận',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              // Dedicated Refresh Button for Remote D-Pad Focus
              SizedBox(
                height: 38,
                child: TvFocusableCard(
                  onTap: () => _loadMatches(forceRefresh: true),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF1E293B),
                    child: const Row(
                      children: [
                        Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8), size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Làm Mới',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main List or Loading / Error
        Expanded(
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF38BDF8)),
                      SizedBox(height: 14),
                      Text('Đang cập nhật lịch đấu mới nhất...', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                )
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off_rounded, color: Colors.amber, size: 48),
                          SizedBox(height: 12),
                          Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 16),
                          TvFocusableCard(
                            onTap: () => _loadMatches(forceRefresh: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: const Color(0xFF38BDF8),
                              child: const Text('Thử lại', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadMatches(forceRefresh: true),
                      color: const Color(0xFF38BDF8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Grid columns adaptive: TV (>1100px: 3 cols, Tablet >650px: 2 cols, Phone: 1 col)
                          int crossAxisCount = 1;
                          if (constraints.maxWidth > 1100) {
                            crossAxisCount = 3;
                          } else if (constraints.maxWidth > 650) {
                            crossAxisCount = 2;
                          }

                          final major = _majorMatches;
                          final others = _otherMatches;

                          return CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            cacheExtent: 350,
                            slivers: [
                              // Khu vực 1: Tâm Điểm & Giải Đấu Hàng Đầu
                              if (major.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '⭐ Tâm Điểm & Giải Đấu Hàng Đầu',
                                    count: major.length.toString(),
                                    color: const Color(0xFFF59E0B),
                                    subtitle: 'Việt Nam • Ngoại Hạng Anh • Cúp C1 • La Liga • Serie A • Bundesliga...',
                                  ),
                                ),
                                _buildMatchGrid(major, crossAxisCount),
                              ],

                              // Khu vực 2: Các Trận Đấu & Giải Đấu Khác (giải cỏ, giải phụ...)
                              if (others.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '🌐 Các Trận Đấu & Giải Đấu Khác',
                                    count: others.length.toString(),
                                    color: const Color(0xFF38BDF8),
                                    subtitle: 'Các giải đấu phụ, giải cỏ và hạng dưới hôm nay',
                                  ),
                                ),
                                _buildMatchGrid(others, crossAxisCount),
                              ],

                              // Fallback nếu không chia được mục nào
                              if (major.isEmpty && others.isEmpty && _matches.isNotEmpty) ...[
                                SliverToBoxAdapter(
                                  child: _buildSectionHeader(
                                    title: '⚽ Tất Cả Trận Đấu Hôm Nay',
                                    count: _matches.length.toString(),
                                    color: const Color(0xFF38BDF8),
                                  ),
                                ),
                                _buildMatchGrid(_matches, crossAxisCount),
                              ],

                              const SliverToBoxAdapter(
                                child: SizedBox(height: 24),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String count,
    required Color color,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.6), width: 0.8),
            ),
            child: Text(
              '$count trận',
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchGrid(List<MatchModel> matches, int crossAxisCount) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          mainAxisExtent: 168,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, idx) => _buildMatchCard(matches[idx]),
          childCount: matches.length,
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: true,
        ),
      ),
    );
  }

  Widget _buildMatchCard(MatchModel match) {
    Color cardBg = const Color(0xFF1E293B);
    Color borderColor = const Color(0xFF334155);
    Color focusBorder = const Color(0xFF38BDF8);

    if (match.isVietnam) {
      cardBg = const Color(0xFF500724).withOpacity(0.7);
      borderColor = const Color(0xFFDC2626);
      focusBorder = const Color(0xFFFDE047);
    } else if (match.isMuFavorite) {
      cardBg = const Color(0xFF450A0A).withOpacity(0.7);
      borderColor = const Color(0xFF991B1B);
      focusBorder = const Color(0xFFEF4444);
    } else if (match.isFavorite) {
      cardBg = const Color(0xFF422006).withOpacity(0.7);
      borderColor = const Color(0xFFB45309);
      focusBorder = const Color(0xFFF59E0B);
    } else if (match.isFamous) {
      cardBg = const Color(0xFF0C2444).withOpacity(0.6);
      borderColor = const Color(0xFF0284C7);
      focusBorder = const Color(0xFF38BDF8);
    } else if (match.isHot) {
      cardBg = const Color(0xFF312E81).withOpacity(0.5);
      borderColor = const Color(0xFF4F46E5);
      focusBorder = const Color(0xFF818CF8);
    }

    Widget footerWidget;
    if (match.isVietnam) {
      footerWidget = const Text('⭐ BÓNG ĐÁ VIỆT NAM ⭐', style: TextStyle(color: Color(0xFFFDE047), fontSize: 10, fontWeight: FontWeight.bold));
    } else if (match.isMuFavorite) {
      footerWidget = const Text('⭐ MANCHESTER UNITED ⭐', style: TextStyle(color: Color(0xFFFDE047), fontSize: 10, fontWeight: FontWeight.bold));
    } else if (match.isFavorite && match.favoriteBadgeText.isNotEmpty) {
      footerWidget = Text('⭐ TÂM ĐIỂM: ${match.favoriteBadgeText} ⭐', style: const TextStyle(color: Color(0xFFFDBA74), fontSize: 10, fontWeight: FontWeight.bold));
    } else if (match.isFamous) {
      footerWidget = Text('🔥 ${match.league.toUpperCase()} 🔥', style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis);
    } else if (match.isHot) {
      footerWidget = const Text('🔥 TRẬN ĐẤU TÂM ĐIỂM 🔥', style: TextStyle(color: Color(0xFFFDBA74), fontSize: 10, fontWeight: FontWeight.bold));
    } else {
      footerWidget = const Text('Bình luận tiếng Việt • Full HD', style: TextStyle(color: Color(0xFF64748B), fontSize: 10));
    }

    return TvFocusableCard(
      onTap: () => _onMatchSelected(match),
      focusBorderColor: focusBorder,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header: League & Time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    match.league,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: match.isLive ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF0284C7).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: match.isLive ? Colors.redAccent.withOpacity(0.6) : const Color(0xFF38BDF8).withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        match.isLive ? Icons.fiber_manual_record : Icons.access_time_rounded,
                        color: match.isLive ? Colors.redAccent : const Color(0xFF38BDF8),
                        size: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        match.isLive ? 'TRỰC TIẾP' : match.time,
                        style: TextStyle(
                          color: match.isLive ? Colors.redAccent : const Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Teams Stacked Rows (Home & Away each get full width)
            Column(
              children: [
                // Home Team
                Row(
                  children: [
                    _buildTeamLogo(match.homeLogo, teamName: match.homeTeam),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match.homeTeam,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Chủ', style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Away Team
                Row(
                  children: [
                    _buildTeamLogo(match.awayLogo, teamName: match.awayTeam),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match.awayTeam,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Khách', style: TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),

            // Footer Tags (MU / Vietnam / Favorite / Normal)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                footerWidget,
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamLogo(String url, {String teamName = ''}) {
    final String initial = teamName.trim().isNotEmpty ? teamName.trim().substring(0, 1).toUpperCase() : '?';

    Widget placeholder = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF334155),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );

    if (url.isEmpty || !url.startsWith('http')) {
      return placeholder;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 32,
          height: 32,
          memCacheWidth: 64,
          memCacheHeight: 64,
          maxWidthDiskCache: 120,
          maxHeightDiskCache: 120,
          fit: BoxFit.contain,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
