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

  /// Automatically converts FLV streams to native HLS (.m3u8) endpoints.
  /// Apple AVPlayer (iOS/macOS) does not support .flv and fails with error -12939.
  static String convertFlvToHls(String rawUrl) {
    if (rawUrl.isEmpty) return rawUrl;
    var u = rawUrl.trim();
    if (u.contains('cdnflv.xbdbotv.live/live/')) {
      return u.replaceAll('cdnflv.xbdbotv.live/live/', 'cdnhls.xbdbotv.live/live/').replaceAll(RegExp(r'\.flv(\?|$)', caseSensitive: false), r'/index.m3u8$1');
    }
    if (u.contains('flv.lauthaitv.cc/live/')) {
      return u.replaceAll('flv.lauthaitv.cc/live/', 'hls.lauthaitv.cc/live/').replaceAll(RegExp(r'\.flv(\?|$)', caseSensitive: false), r'/index.m3u8$1');
    }
    if (u.contains('zundrixmediapipeline.com') || u.contains('meung.app') || u.contains('zktsva.app')) {
      return u.replaceAll(RegExp(r'\.flv(\?|$)', caseSensitive: false), r'.m3u8$1');
    }
    final mDomain = RegExp(r'domaincdn\.cc/livecdn/channel-?(\d+)\.flv', caseSensitive: false).firstMatch(u);
    if (mDomain != null) {
      return 'https://live2.zundrixmediapipeline.com/live/channel${mDomain.group(1)}.m3u8';
    }
    final mPro2 = RegExp(r'pro2cdnlive\.com/live/channel-?(\d+)\.flv', caseSensitive: false).firstMatch(u);
    if (mPro2 != null) {
      return 'https://live2.zundrixmediapipeline.com/live/channel${mPro2.group(1)}.m3u8';
    }
    if (u.contains('.flv')) {
      return u.replaceAll(RegExp(r'\.flv(\?|$)', caseSensitive: false), r'.m3u8$1');
    }
    return u;
  }

  /// Resolves the actual playback stream URL.
  /// If the stream specifies custom Referer headers, routes through the VPS proxy to bypass CDN 403 Forbidden.
  String getPlaybackUrl({String? baseUrl}) {
    final bool hasReferer = headers.containsKey('Referer') || headers.containsKey('referer');
    if (hasReferer && proxyUrl.isNotEmpty) {
      if (proxyUrl.startsWith('http://') || proxyUrl.startsWith('https://')) {
        return convertFlvToHls(proxyUrl);
      }
      if (baseUrl != null && baseUrl.isNotEmpty) {
        final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
        final cleanProxy = proxyUrl.startsWith('/') ? proxyUrl : '/$proxyUrl';
        return convertFlvToHls('$cleanBase$cleanProxy');
      }
    }
    return convertFlvToHls(url);
  }

  /// Converts this channel to a StreamChannel for VideoPlayerScreen
  StreamChannel toStreamChannel({String? baseUrl}) {
    final finalUrl = getPlaybackUrl(baseUrl: baseUrl);
    final isProxied = finalUrl.contains('/api/iptv/stream-proxy');
    return StreamChannel(
      name: group,
      title: name.replaceAll(RegExp(r'\[flv\]', caseSensitive: false), '[HLS]').replaceAll(RegExp(r'\(flv\)', caseSensitive: false), '(HLS)'),
      url: finalUrl,
      headers: isProxied ? const {} : headers,
    );
  }
}
