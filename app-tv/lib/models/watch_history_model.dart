class WatchHistoryItem {
  final String id; // Unique key: 'anime:123:ep:5' hoặc 'movie:vlxx:456'
  final String mediaId; // ID gốc (anime.id hoặc movie.id)
  final String title; // Tên phim / Anime
  final String subtitle; // Tên tập hoặc chất lượng / server
  final String poster; // URL poster ảnh bìa
  final String streamUrl; // Link luồng phát trực tiếp
  final int positionMs; // Vị trí đã xem (milliseconds)
  final int durationMs; // Tổng thời lượng (milliseconds)
  final String category; // 'anime' | 'secret'
  final int episode; // Số tập (đối với anime)
  final int season; // Mùa phim
  final String updatedAt; // Thời điểm cập nhật (ISO 8601)

  const WatchHistoryItem({
    required this.id,
    required this.mediaId,
    required this.title,
    this.subtitle = '',
    this.poster = '',
    this.streamUrl = '',
    required this.positionMs,
    required this.durationMs,
    this.category = 'anime',
    this.episode = 0,
    this.season = 0,
    required this.updatedAt,
  });

  int get position => positionMs;
  int get duration => durationMs;

  /// Kiểm tra xem phim có đang ở trạng thái xem dở hay không
  /// - Bỏ qua xem lướt: < 15 giây
  /// - Xem xong: >= 95% thời lượng hoặc còn dưới 30 giây cuối
  /// - Đang xem dở: 15s <= position < 95% và còn > 30s
  bool get isInProgress {
    if (durationMs <= 0) return positionMs > 15000;
    final double pct = positionMs / durationMs;
    final int remainMs = durationMs - positionMs;
    return positionMs >= 15000 && pct < 0.95 && remainMs > 30000;
  }

  /// Tỷ lệ phần trăm đã xem (0.0 -> 1.0)
  double get progressPercent {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  /// Định dạng vị trí hiện tại: mm:ss hoặc hh:mm:ss
  String get formattedPosition => _formatDurationMs(positionMs);

  /// Định dạng tổng thời lượng: mm:ss hoặc hh:mm:ss
  String get formattedDuration => _formatDurationMs(durationMs);

  static String _formatDurationMs(int ms) {
    if (ms <= 0) return '00:00';
    final int totalSec = ms ~/ 1000;
    final int hours = totalSec ~/ 3600;
    final int minutes = (totalSec % 3600) ~/ 60;
    final int seconds = totalSec % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mediaId': mediaId,
      'title': title,
      'subtitle': subtitle,
      'poster': poster,
      'streamUrl': streamUrl,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'category': category,
      'episode': episode,
      'season': season,
      'updatedAt': updatedAt,
    };
  }

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return WatchHistoryItem(
      id: json['id']?.toString() ?? '',
      mediaId: json['mediaId']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      poster: json['poster']?.toString() ?? '',
      streamUrl: json['streamUrl']?.toString() ?? '',
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? 'anime',
      episode: (json['episode'] as num?)?.toInt() ?? 0,
      season: (json['season'] as num?)?.toInt() ?? 0,
      updatedAt: json['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}
