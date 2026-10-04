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

class FootballPriorityResult {
  final int priorityLevel;
  final bool isFamous;
  final bool isVietnam;
  final bool isHot;

  const FootballPriorityResult({
    required this.priorityLevel,
    required this.isFamous,
    required this.isVietnam,
    required this.isHot,
  });
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
  final bool isHot;

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
    this.isHot = false,
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

  /// Parses match kickoff time into local DateTime.
  DateTime? get matchStartTime {
    final targetStr = matchTime.isNotEmpty ? matchTime : name;
    final regex = RegExp(r'(\d{1,2}):(\d{2})(\s*[-/ ]\s*(\d{1,2})[\./-](\d{1,2}))?');
    final m = regex.firstMatch(targetStr);
    if (m != null) {
      final hour = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      final now = DateTime.now();
      int day = now.day;
      int month = now.month;
      if (m.group(4) != null && m.group(5) != null) {
        day = int.parse(m.group(4)!);
        month = int.parse(m.group(5)!);
      }
      int year = now.year;
      if (now.month == 12 && month == 1) year++;
      return DateTime(year, month, day, hour, min);
    }
    if (matchTimestamp > 0) {
      return DateTime.fromMillisecondsSinceEpoch(matchTimestamp);
    }
    return null;
  }

  /// Calculates elapsed minutes since kickoff. Returns null if start time is unknown.
  int? get elapsedMinutes {
    final start = matchStartTime;
    if (start == null) return null;
    return DateTime.now().difference(start).inMinutes;
  }

  /// Returns true if the sports match started > 100-115 min ago (already finished / 2 tiếng trước),
  /// or if title explicitly indicates the match has ended ("Hết giờ", "FT", "Kết thúc").
  bool get isFinishedMatch {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('hết giờ') || lowerName.contains('ft ') || lowerName.endsWith('ft') || lowerName.contains('kết thúc')) {
      return true;
    }
    if (category != 'FOOTBALL' && category != 'OTHER_SPORTS') return false;
    final elapsed = elapsedMinutes;
    if (elapsed == null) return false;
    return elapsed > (isLive ? 115 : 100);
  }

  /// Returns true if the sports match is currently ongoing (within 90 mins of kickoff, or live within 110 mins).
  bool get isOngoingNow {
    if (category != 'FOOTBALL' && category != 'OTHER_SPORTS') return isLive;
    if (isFinishedMatch) return false;
    final elapsed = elapsedMinutes;
    if (elapsed == null) return isLive;
    return elapsed >= -5 && elapsed <= (isLive ? 115 : 100);
  }

  /// Human-readable match minute label, e.g. "Phút 45'", "Hiệp 2", or "TRỰC TIẾP"
  String get liveMinuteLabel {
    final elapsed = elapsedMinutes;
    if (elapsed == null || elapsed < 0) return 'TRỰC TIẾP';
    if (elapsed <= 45) return "Phút $elapsed'";
    if (elapsed <= 60) return "Hiệp 2";
    if (elapsed <= 90) return "Phút $elapsed'";
    return "Phút 90+'";
  }

  /// Classifies Football match priority client-side:
  /// 1. Việt Nam Football & Manchester United (Priority 1)
  /// 2. Major Leagues, Top Clubs & Major National Teams (Priority 2)
  /// 3. Other matches / Obscure leagues (Priority 3)
  static FootballPriorityResult classifyFootballPriority(String name, String group) {
    final String q = ' $name $group '.toLowerCase();

    // Check Esports
    final bool esportsDetected = q.contains('esport') ||
        q.contains('dota') ||
        q.contains('cs:go') ||
        q.contains('cs2') ||
        q.contains('counter-strike') ||
        q.contains('crossfire') ||
        q.contains('đột kích') ||
        q.contains('league of legends') ||
        q.contains('demacia cup') ||
        q.contains('cct') ||
        q.contains('esl') ||
        q.contains('european pro league') ||
        q.contains('lcs') ||
        q.contains('lck') ||
        q.contains('valorant') ||
        q.contains('pubg') ||
        q.contains('arena of valor') ||
        q.contains('tốc chiến') ||
        q.contains('liên quân');

    // Check lower / secondary leagues & women leagues (except Vietnam)
    final bool isLowerOrWomenLeague = q.contains('la liga 2') ||
        q.contains('segunda') ||
        q.contains('hypermotion') ||
        q.contains('bundesliga 2') ||
        q.contains('2. bundesliga') ||
        q.contains('serie b') ||
        q.contains('serie c') ||
        q.contains('ligue 2') ||
        q.contains('hạng 2') ||
        q.contains('hạng 3') ||
        q.contains('u17') ||
        q.contains('u19') ||
        q.contains('u21') ||
        (q.contains('frauen') && !q.contains('việt nam')) ||
        (q.contains('women') && !q.contains('việt nam')) ||
        (q.contains('nữ') && !q.contains('việt nam'));

    if (esportsDetected || isLowerOrWomenLeague) {
      return const FootballPriorityResult(priorityLevel: 3, isFamous: false, isVietnam: false, isHot: false);
    }

    // 1. Vietnam Football (Priority 1)
    final bool isVn = q.contains('việt nam') ||
        q.contains('viet nam') ||
        q.contains('vietnam') ||
        q.contains('u23 việt nam') ||
        q.contains('u22 việt nam') ||
        q.contains('u19 việt nam') ||
        q.contains('u21 việt nam') ||
        q.contains('đt việt nam') ||
        q.contains('đội tuyển việt nam') ||
        q.contains('đt nữ việt nam') ||
        q.contains('v-league') ||
        q.contains('vleague') ||
        q.contains('v.league') ||
        q.contains('v league') ||
        q.contains('cúp quốc gia') ||
        q.contains('hạng nhất quốc gia') ||
        q.contains('nam định') ||
        q.contains('hà nội fc') ||
        q.contains('clb hà nội') ||
        q.contains('công an hà nội') ||
        q.contains('cahn') ||
        q.contains('thể công') ||
        q.contains('viettel') ||
        q.contains('hagl') ||
        q.contains('hoàng anh gia lai') ||
        q.contains('sông lam nghệ an') ||
        q.contains('slna') ||
        q.contains('thanh hóa') ||
        q.contains('bình định') ||
        q.contains('hải phòng') ||
        q.contains('bình dương') ||
        q.contains('becamex') ||
        q.contains('tp.hồ chí minh') ||
        q.contains('tp hcm') ||
        q.contains('đà nẵng') ||
        q.contains('quảng nam') ||
        q.contains('hà tĩnh') ||
        q.contains('khánh hòa') ||
        q.contains('pvf');

    if (isVn) {
      return const FootballPriorityResult(priorityLevel: 1, isFamous: true, isVietnam: true, isHot: true);
    }

    // 1b. Manchester United (Priority 1)
    final bool isMu = q.contains('manchester united') ||
        q.contains('man utd') ||
        q.contains('man united') ||
        q.contains('manchester utd') ||
        q.contains('man u ') ||
        q.contains(' mu ') ||
        q.endsWith(' mu') ||
        q.startsWith('mu ') ||
        RegExp(r'(^|\s|[\[(])mu(\s|[\])]|$)').hasMatch(q);

    if (isMu) {
      return const FootballPriorityResult(priorityLevel: 1, isFamous: true, isVietnam: false, isHot: true);
    }

    // 2a. Big Clubs & Major National Teams (Priority 2)
    final List<String> bigTeams = [
      'manchester city', 'man city', 'mancity', ' mc ',
      'liverpool', 'arsenal', 'chelsea', 'tottenham', 'spurs',
      'aston villa', 'newcastle', 'brighton', 'brentford',
      'real madrid', 'barcelona', 'barca', 'atletico madrid', 'atletico',
      'bayern munich', 'bayern', 'dortmund', 'bvb', 'leverkusen', 'bayer leverkusen',
      'paris saint-germain', 'psg', 'paris sg',
      'juventus', 'juve', 'inter milan', 'ac milan', 'as roma', ' roma ', 'napoli',
      'al nassr', 'al-nassr', 'al hilal', 'al-hilal', 'al ittihad', 'al-ittihad',
      'inter miami', 'benfica', 'porto', 'sporting lisbon', 'sporting cp',
      // Major National Teams
      'đt anh', 'tuyển anh', 'england',
      'đt pháp', 'tuyển pháp', 'france',
      'đt đức', 'tuyển đức', 'germany',
      'đt ý', 'tuyển ý', 'italy',
      'đt tây ban nha', 'tuyển tây ban nha', 'spain',
      'đt bồ đào nha', 'tuyển bồ đào nha', 'portugal',
      'đt hà lan', 'tuyển hà lan', 'netherlands',
      'đt bỉ', 'tuyển bỉ', 'belgium',
      'đt argentina', 'tuyển argentina',
      'đt brazil', 'tuyển brazil',
      'đt nhật bản', 'tuyển nhật bản', 'japan',
      'đt hàn quốc', 'tuyển hàn quốc', 'korea',
      'đt ai cập', 'tuyển ai cập', 'ai cập', 'egypt',
      'đt ma rốc', 'tuyển ma rốc', 'ma rốc', 'morocco',
      'đt nam phi', 'nam phi', 'south africa',
      'đt senegal', 'senegal',
      'đt nigeria', 'nigeria',
      'đt mali', 'mali',
    ];

    for (final t in bigTeams) {
      if (q.contains(t)) {
        return const FootballPriorityResult(priorityLevel: 2, isFamous: true, isVietnam: false, isHot: true);
      }
    }

    // Match Argentina / Brazil as actual playing teams (avoid league names like VĐQG Argentina)
    final bool isArgentinaOrBrazilPlaying = RegExp(r'(^|[\s⚽/–—-])(argentina|brazil)([\s/–—-]*(vs|v|\(|$))').hasMatch(q) ||
        RegExp(r'(vs|v)\s*(argentina|brazil)([\s/–—-]|\(|$)').hasMatch(q);
    if (isArgentinaOrBrazilPlaying) {
      return const FootballPriorityResult(priorityLevel: 2, isFamous: true, isVietnam: false, isHot: true);
    }

    // 2b. Major & Famous Worldwide Leagues (Priority 2)
    final List<String> majorLeagues = [
      'premier league', 'ngoại hạng anh', 'epl', 'fa cup', 'cúp fa', 'carabao', 'efl cup',
      'champions league', 'cúp c1', 'uefa champions', 'ucl',
      'europa league', 'cúp c2', 'uefa europa', 'uel',
      'conference league', 'cúp c3', 'uefa conference', 'uecl',
      'siêu cúp châu âu', 'super cup',
      'la liga', 'vđqg tây ban nha', 'copa del rey', 'cúp nhà vua', 'supercopa',
      'serie a', 'vđqg ý', 'coppa italia', 'cúp ý', 'supercoppa italiana',
      'bundesliga', 'vđqg đức', 'dfb-pokal', 'cúp qg đức', 'dfl-supercup',
      'ligue 1', 'vđqg pháp', 'coupe de france', 'cúp qg pháp',
      'world cup', 'vòng loại world cup', 'uefa euro', 'vòng loại euro', 'euro 2024', 'euro 2028', 'cúp euro',
      'nations league', 'copa america', 'asian cup', 'afc champions league', 'cúp c1 châu á', 'cúp c2 châu á',
      'shopee cup', 'aff cup', 'asean cup', 'sea games', 'olympic',
      'afcon', 'cúp châu phi', 'african cup', 'can 20', 'can 202',
      'concacaf', 'gold cup', 'giao hữu quốc tế', 'international friendly',
      'saudi pro league', 'saudi league', 'mls', 'major league soccer', 'nhà nghề mỹ'
    ];

    for (final l in majorLeagues) {
      if (q.contains(l)) {
        return const FootballPriorityResult(priorityLevel: 2, isFamous: true, isVietnam: false, isHot: true);
      }
    }

    // 2c. Scraper / UI Hot Badges
    if (name.contains('🔥') || q.contains('tâm điểm') || q.contains('trận hot')) {
      return const FootballPriorityResult(priorityLevel: 2, isFamous: true, isVietnam: false, isHot: true);
    }

    // 3. Normal / Minor matches
    return const FootballPriorityResult(priorityLevel: 3, isFamous: false, isVietnam: false, isHot: false);
  }

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
    final rawGroup = json['group']?.toString() ?? 'Chung';

    final String rawCat = json['category']?.toString() ?? '';
    String parsedCategory = rawCat;
    if (parsedCategory.isEmpty || parsedCategory == 'FIXED_TV') {
      final q = '$rawName $rawGroup'.toLowerCase();
      final hasTimePattern = RegExp(r'\d{1,2}:\d{2}').hasMatch(rawName);
      final hasVs = q.contains(' vs ') || q.contains(' v ') || q.contains(' u21 ') || q.contains(' u23 ') || q.contains(' u19 ');
      if (rawName.contains('⚽') ||
          (hasTimePattern && hasVs) ||
          q.contains('vua sân cỏ') ||
          q.contains('khán đài') ||
          q.contains('xôi lạc') ||
          q.contains('sút bóng') ||
          q.contains('cola tv') ||
          q.contains('giờ vàng') ||
          q.contains('bóng đá')) {
        parsedCategory = 'FOOTBALL';
      }
    }

    int priority = json['priorityLevel'] is int
        ? json['priorityLevel']
        : (int.tryParse(json['priorityLevel']?.toString() ?? '3') ?? 3);
    bool famous = json['isFamous'] == true;
    bool vn = json['isVietnam'] == true;
    bool hot = json['isHot'] == true;

    // Client-side fallback / reinforcement for Football matches
    if (parsedCategory == 'FOOTBALL' || rawName.contains('⚽') || rawGroup.toLowerCase().contains('bóng đá')) {
      final classified = classifyFootballPriority(rawName, rawGroup);
      if (classified.priorityLevel < priority) {
        priority = classified.priorityLevel;
      }
      if (classified.isFamous) famous = true;
      if (classified.isVietnam) vn = true;
      if (classified.isHot) hot = true;
    }

    return IptvChannelModel(
      id: json['id']?.toString() ?? '',
      name: rawName,
      cleanTitle: parsedCleanTitle.isNotEmpty ? parsedCleanTitle : extractCleanTitle(rawName),
      logo: json['logo']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      proxyUrl: json['proxyUrl']?.toString() ?? '',
      group: rawGroup,
      headers: parsedHeaders,
      isPinned: json['isPinned'] == true,
      isHidden: json['isHidden'] == true,
      sourceId: json['sourceId']?.toString() ?? 'pl-default',
      sourceName: json['sourceName']?.toString() ?? 'Kênh Quốc Gia',
      isLive: json['isLive'] == true,
      matchTime: parsedMatchTime.isNotEmpty ? parsedMatchTime : extractMatchTime(rawName),
      matchTimestamp: json['matchTimestamp'] is int ? json['matchTimestamp'] : (int.tryParse(json['matchTimestamp']?.toString() ?? '0') ?? 0),
      category: parsedCategory.isNotEmpty ? parsedCategory : 'FIXED_TV',
      priorityLevel: priority,
      isFamous: famous,
      isVietnam: vn,
      isHot: hot,
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
      'isHot': isHot,
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
