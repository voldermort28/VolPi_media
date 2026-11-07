class TelegramSourceModel {
  final String id;
  final String name;
  final String channelId;
  final String url;
  final bool enabled;
  final int count;
  final String? createdAt;

  const TelegramSourceModel({
    required this.id,
    required this.name,
    required this.channelId,
    required this.url,
    this.enabled = true,
    this.count = 0,
    this.createdAt,
  });

  factory TelegramSourceModel.fromJson(Map<String, dynamic> json) {
    return TelegramSourceModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Kênh Telegram',
      channelId: json['channelId'] as String? ?? '',
      url: json['url'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
      count: (json['count'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String?,
    );
  }
}

class TelegramVideoModel {
  final int id;
  final String channelId;
  final String title;
  final String fileName;
  final String caption;
  final int size;
  final String formattedSize;
  final int duration;
  final String formattedDuration;
  final int width;
  final int height;
  final String mimeType;
  final String? thumbnailUrl;
  final int date;

  const TelegramVideoModel({
    required this.id,
    required this.channelId,
    required this.title,
    this.fileName = '',
    this.caption = '',
    this.size = 0,
    this.formattedSize = '',
    this.duration = 0,
    this.formattedDuration = '',
    this.width = 0,
    this.height = 0,
    this.mimeType = 'video/mp4',
    this.thumbnailUrl,
    this.date = 0,
  });

  factory TelegramVideoModel.fromJson(Map<String, dynamic> json) {
    return TelegramVideoModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      channelId: json['channelId'] as String? ?? '',
      title: json['title'] as String? ?? 'Video',
      fileName: json['fileName'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      formattedSize: json['formattedSize'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      formattedDuration: json['formattedDuration'] as String? ?? '',
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String? ?? 'video/mp4',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      date: (json['date'] as num?)?.toInt() ?? 0,
    );
  }
}

class TelegramChannelVideosResult {
  final String channelId;
  final String channelTitle;
  final List<TelegramVideoModel> videos;
  final int total;

  const TelegramChannelVideosResult({
    required this.channelId,
    required this.channelTitle,
    required this.videos,
    required this.total,
  });

  factory TelegramChannelVideosResult.fromJson(Map<String, dynamic> json) {
    final videoList = (json['videos'] as List?)
            ?.map((e) => TelegramVideoModel.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return TelegramChannelVideosResult(
      channelId: json['channelId'] as String? ?? '',
      channelTitle: json['channelTitle'] as String? ?? '',
      videos: videoList,
      total: (json['total'] as num?)?.toInt() ?? videoList.length,
    );
  }
}
