import 'match_model.dart';

class IptvSourceModel {
  final String id;
  final String name;
  final int count;

  const IptvSourceModel({
    required this.id,
    required this.name,
    this.count = 0,
  });

  factory IptvSourceModel.fromJson(Map<String, dynamic> json) {
    return IptvSourceModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Nguồn',
      count: json['count'] is int ? json['count'] : 0,
    );
  }
}

class IptvChannelModel {
  final String id;
  final String name;
  final String logo;
  final String url;
  final String proxyUrl;
  final String group;
  final Map<String, String> headers;
  final bool isPinned;
  final bool isHidden;
  final String sourceId;
  final String sourceName;

  const IptvChannelModel({
    required this.id,
    required this.name,
    this.logo = '',
    required this.url,
    this.proxyUrl = '',
    this.group = 'Chung',
    this.headers = const {},
    this.isPinned = false,
    this.isHidden = false,
    this.sourceId = 'pl-default',
    this.sourceName = 'Kênh Quốc Gia',
  });

  factory IptvChannelModel.fromJson(Map<String, dynamic> json) {
    Map<String, String> parsedHeaders = {};
    if (json['headers'] is Map) {
      (json['headers'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          parsedHeaders[k.toString()] = v.toString();
        }
      });
    }

    return IptvChannelModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Kênh truyền hình',
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      proxyUrl: json['proxyUrl']?.toString() ?? '',
      group: json['group']?.toString() ?? 'Chung',
      headers: parsedHeaders,
      isPinned: json['isPinned'] == true,
      isHidden: json['isHidden'] == true,
      sourceId: json['sourceId']?.toString() ?? 'pl-default',
      sourceName: json['sourceName']?.toString() ?? 'Kênh Quốc Gia',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo': logo,
      'url': url,
      'proxyUrl': proxyUrl,
      'group': group,
      'headers': headers,
      'isPinned': isPinned,
      'isHidden': isHidden,
      'sourceId': sourceId,
      'sourceName': sourceName,
    };
  }

  /// Resolves the actual playback stream URL.
  /// If the stream specifies custom Referer headers, routes through the VPS proxy to bypass CDN 403 Forbidden.
  String getPlaybackUrl({String? baseUrl}) {
    final bool hasReferer = headers.containsKey('Referer') || headers.containsKey('referer');
    if (hasReferer && proxyUrl.isNotEmpty) {
      if (proxyUrl.startsWith('http://') || proxyUrl.startsWith('https://')) {
        return proxyUrl;
      }
      if (baseUrl != null && baseUrl.isNotEmpty) {
        final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final cleanProxy = proxyUrl.startsWith('/') ? proxyUrl : '/$proxyUrl';
        return '$cleanBase$cleanProxy';
      }
    }
    return url;
  }

  /// Converts this channel to a StreamChannel for VideoPlayerScreen
  StreamChannel toStreamChannel({String? baseUrl}) {
    return StreamChannel(
      name: group,
      title: name,
      url: getPlaybackUrl(baseUrl: baseUrl),
      headers: headers,
    );
  }
}
