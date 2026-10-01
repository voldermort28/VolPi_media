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
  final String cleanTitle;
  final String logo;
  final String url;
  final String proxyUrl;
  final String group;
  final Map<String, String> headers;
  final bool isPinned;
  final bool isHidden;
  final String sourceId;
  final String sourceName;
  final bool isLive;
  final String matchTime;
  final int matchTimestamp;
  final String category;
  final int priorityLevel;
  final bool isFamous;
  final bool isVietnam;

  const IptvChannelModel({
    required this.id,
    required this.name,
    this.cleanTitle = '',
    this.logo = '',
    required this.url,
    this.proxyUrl = '',
    this.group = 'Chung',
    this.headers = const {},
    this.isPinned = false,
    this.isHidden = false,
    this.sourceId = 'pl-default',
    this.sourceName = 'Kênh Quốc Gia',
    this.isLive = false,
    this.matchTime = '',
    this.matchTimestamp = 0,
    this.category = 'FIXED_TV',
    this.priorityLevel = 3,
    this.isFamous = false,
    this.isVietnam = false,
  });

  static String extractCleanTitle(String rawName) {
    if (rawName.isEmpty) return '';
    final timeMatch = RegExp(r'\d{1,2}:\d{2}(\s+\d{1,2}[\/\.-]\d{1,2})?').firstMatch(rawName);
    if (timeMatch != null) {
      var after = rawName.substring(timeMatch.end).trim();
      after = after.replaceFirst(RegExp(r'^[\s\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\-–—:]+', unicode: true), '').trim();
      if (after.isNotEmpty) return after;
    }
    var cleaned = rawName.replaceFirst(RegExp(r'^[\s\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\-–—:]+', unicode: true), '').trim();
    return cleaned.isNotEmpty ? cleaned : rawName;
  }

  static String extractMatchTime(String rawName) {
    final timeMatch = RegExp(r'\d{1,2}:\d{2}(\s+\d{1,2}[\/\.-]\d{1,2})?').firstMatch(rawName);
    return timeMatch != null ? timeMatch.group(0)! : '';
  }

  String get displayTitle => cleanTitle.isNotEmpty ? cleanTitle : extractCleanTitle(name);
  String get displayTime => matchTime.isNotEmpty ? matchTime : extractMatchTime(name);

  factory IptvChannelModel.fromJson(Map<String, dynamic> json) {
    Map<String, String> parsedHeaders = {};
    if (json['headers'] is Map) {
      (json['headers'] as Map).forEach((k, v) {
        if (k != null && v != null) {
          parsedHeaders[k.toString()] = v.toString();
        }
      });
    }

    final rawName = json['name']?.toString() ?? 'Kênh truyền hình';
    final parsedCleanTitle = json['cleanTitle']?.toString() ?? '';
    final parsedMatchTime = json['matchTime']?.toString() ?? '';

    return IptvChannelModel(
      id: json['id']?.toString() ?? '',
      name: rawName,
      cleanTitle: parsedCleanTitle.isNotEmpty ? parsedCleanTitle : extractCleanTitle(rawName),
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      proxyUrl: json['proxyUrl']?.toString() ?? '',
      group: json['group']?.toString() ?? 'Chung',
      headers: parsedHeaders,
      isPinned: json['isPinned'] == true,
      isHidden: json['isHidden'] == true,
      sourceId: json['sourceId']?.toString() ?? 'pl-default',
      sourceName: json['sourceName']?.toString() ?? 'Kênh Quốc Gia',
      isLive: json['isLive'] == true,
      matchTime: parsedMatchTime.isNotEmpty ? parsedMatchTime : extractMatchTime(rawName),
      matchTimestamp: json['matchTimestamp'] is int ? json['matchTimestamp'] : (int.tryParse(json['matchTimestamp']?.toString() ?? '0') ?? 0),
      category: json['category']?.toString() ?? 'FIXED_TV',
      priorityLevel: json['priorityLevel'] is int ? json['priorityLevel'] : (int.tryParse(json['priorityLevel']?.toString() ?? '3') ?? 3),
      isFamous: json['isFamous'] == true,
      isVietnam: json['isVietnam'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cleanTitle': cleanTitle,
      'logo': logo,
      'url': url,
      'proxyUrl': proxyUrl,
      'group': group,
      'headers': headers,
      'isPinned': isPinned,
      'isHidden': isHidden,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'isLive': isLive,
      'matchTime': matchTime,
      'matchTimestamp': matchTimestamp,
      'category': category,
      'priorityLevel': priorityLevel,
      'isFamous': isFamous,
      'isVietnam': isVietnam,
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
