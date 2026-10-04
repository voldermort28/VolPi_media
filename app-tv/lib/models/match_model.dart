class MatchModel {
  final String id;
  final String slug;
  final String title;
  final String time;
  final String league;
  final String homeTeam;
  final String awayTeam;
  final String homeLogo;
  final String awayLogo;
  final String poster;
  final String description;
  final bool isVietnam;
  final bool isMuFavorite;
  final bool isFavorite;
  final bool isFamous;
  final bool isHot;
  final bool isEsports;
  final String favoriteBadgeText;
  final bool isLive;
  final int matchTimestamp;

  MatchModel({
    required this.id,
    required this.slug,
    required this.title,
    required this.time,
    required this.league,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeLogo,
    required this.awayLogo,
    required this.poster,
    required this.description,
    this.isVietnam = false,
    this.isMuFavorite = false,
    this.isFavorite = false,
    this.isFamous = false,
    this.isHot = false,
    this.isEsports = false,
    this.favoriteBadgeText = '',
    this.isLive = false,
    this.matchTimestamp = 0,
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final String rawTitle = json['name'] ?? json['title'] ?? '';
    final String desc = json['description'] ?? '';
    final String id = json['id'] ?? '';
    final String slug = (json['slug'] != null && json['slug'].toString().isNotEmpty)
        ? json['slug']
        : id.replaceFirst('xoilac:', '');

    String league = json['league'] ?? 'Bóng đá';
    String time = json['time'] ?? 'Đang diễn ra';
    String home = json['homeTeam'] ?? '';
    String away = json['awayTeam'] ?? '';

    if (home.isEmpty || away.isEmpty) {
      if (desc.isNotEmpty) {
        final leagueMatch = RegExp(r'🏆\s*([^•\n]+)').firstMatch(desc);
        if (leagueMatch != null) league = leagueMatch.group(1)!.trim();

        final timeMatch = RegExp(r'⏱️\s*([^\n]+)').firstMatch(desc);
        if (timeMatch != null) time = timeMatch.group(1)!.trim();

        final vsMatch = RegExp(r'⚽\s*([^v]+)\s+vs\s+([^\n]+)').firstMatch(desc);
        if (vsMatch != null) {
          home = vsMatch.group(1)!.trim();
          away = vsMatch.group(2)!.trim();
        }
      }
    }
    final String homeLogo = json['homeLogo'] ?? '';
    final String awayLogo = json['awayLogo'] ?? '';
    final String logoText = '$homeLogo $awayLogo'.toLowerCase();
    final String leagueLower = league.toLowerCase();

    final String allText = '$rawTitle $desc $league $home $away'.toLowerCase();

    // Check Esports (Dota 2, CS:GO, LOL, Crossfire, etc.)
    final bool esportsDetected = allText.contains('esport') ||
        allText.contains('dota') ||
        allText.contains('cs:go') ||
        allText.contains('cs2') ||
        allText.contains('counter-strike') ||
        allText.contains('crossfire') ||
        allText.contains('đột kích') ||
        allText.contains('league of legends') ||
        allText.contains('demacia cup') ||
        allText.contains('cct') ||
        allText.contains('esl') ||
        allText.contains('european pro league') ||
        allText.contains('lcs') ||
        allText.contains('lck') ||
        allText.contains('valorant') ||
        allText.contains('pubg') ||
        allText.contains('arena of valor') ||
        allText.contains('tốc chiến') ||
        allText.contains('liên quân') ||
        logoText.contains('/dota') ||
        logoText.contains('/csgo') ||
        logoText.contains('/cs2') ||
        logoText.contains('/lol/') ||
        logoText.contains('/crossfire') ||
        logoText.contains('/esport');

    // Exclude lower division leagues and women leagues (except ĐT Nữ Việt Nam)
    final bool isLowerOrWomenLeague = leagueLower.contains('la liga 2') ||
        leagueLower.contains('segunda') ||
        leagueLower.contains('hypermotion') ||
        leagueLower.contains('bundesliga 2') ||
        leagueLower.contains('2. bundesliga') ||
        leagueLower.contains('serie b') ||
        leagueLower.contains('serie c') ||
        leagueLower.contains('ligue 2') ||
        leagueLower.contains('hạng 2') ||
        leagueLower.contains('hạng 3') ||
        leagueLower.contains('u17') ||
        leagueLower.contains('u19') ||
        leagueLower.contains('u21') ||
        (leagueLower.contains('frauen') && !allText.contains('việt nam')) ||
        (leagueLower.contains('women') && !allText.contains('việt nam')) ||
        (leagueLower.contains('nữ') && !allText.contains('việt nam'));

    // Check Vietnam Football & Vietnamese Clubs
    final bool isVn = json['isVietnam'] == true ||
        rawTitle.contains('⭐ [VIỆT NAM]') ||
        rawTitle.contains('BÓNG ĐÁ VIỆT NAM') ||
        rawTitle.contains('ĐỘI TUYỂN VIỆT NAM') ||
        allText.contains('việt nam') ||
        allText.contains('viet nam') ||
        allText.contains('vietnam') ||
        allText.contains('u23 việt nam') ||
        allText.contains('u22 việt nam') ||
        allText.contains('u19 việt nam') ||
        allText.contains('u21 việt nam') ||
        allText.contains('đt việt nam') ||
        allText.contains('v-league') ||
        allText.contains('vleague') ||
        allText.contains('v.league') ||
        allText.contains('cúp quốc gia') ||
        allText.contains('hạng nhất quốc gia') ||
        allText.contains('nam định') ||
        allText.contains('hà nội fc') ||
        allText.contains('clb hà nội') ||
        allText.contains('công an hà nội') ||
        allText.contains('cahn') ||
        allText.contains('thể công') ||
        allText.contains('viettel') ||
        allText.contains('hagl') ||
        allText.contains('hoàng anh gia lai') ||
        allText.contains('sông lam nghệ an') ||
        allText.contains('slna') ||
        allText.contains('thanh hóa') ||
        allText.contains('bình định') ||
        allText.contains('hải phòng') ||
        allText.contains('bình dương') ||
        allText.contains('becamex') ||
        allText.contains('tp.hồ chí minh') ||
        allText.contains('tp hcm') ||
        allText.contains('đà nẵng') ||
        allText.contains('quảng nam') ||
        allText.contains('hà tĩnh') ||
        allText.contains('khánh hòa') ||
        allText.contains('pvf');

    // Check Manchester United
    final bool isMu = rawTitle.contains('⭐ [MU') ||
        rawTitle.contains('⭐ MANCHESTER') ||
        allText.contains('manchester united') ||
        allText.contains('man utd') ||
        allText.contains('man united') ||
        RegExp(r'(^|\s)mu(\s|$)').hasMatch(allText);

    // Check User Favorite Teams & Big Teams
    final List<Map<String, dynamic>> favoriteKeywords = [
      {'keys': ['manchester city', 'man city', 'mancity'], 'label': 'MAN CITY'},
      {'keys': ['liverpool'], 'label': 'LIVERPOOL'},
      {'keys': ['arsenal'], 'label': 'ARSENAL'},
      {'keys': ['chelsea'], 'label': 'CHELSEA'},
      {'keys': ['tottenham', 'spurs'], 'label': 'TOTTENHAM'},
      {'keys': ['aston villa'], 'label': 'ASTON VILLA'},
      {'keys': ['newcastle'], 'label': 'NEWCASTLE'},
      {'keys': ['brighton'], 'label': 'BRIGHTON'},
      {'keys': ['brentford'], 'label': 'BRENTFORD'},
      {'keys': ['real madrid'], 'label': 'REAL MADRID'},
      {'keys': ['barcelona', 'barca'], 'label': 'BARCELONA'},
      {'keys': ['atletico madrid', 'atletico'], 'label': 'ATLETICO'},
      {'keys': ['bayern munich', 'bayern'], 'label': 'BAYERN MUNICH'},
      {'keys': ['dortmund', 'bvb'], 'label': 'DORTMUND'},
      {'keys': ['leverkusen', 'bayer leverkusen'], 'label': 'LEVERKUSEN'},
      {'keys': ['paris saint-germain', 'psg', 'paris sg'], 'label': 'PSG'},
      {'keys': ['juventus', 'juve'], 'label': 'JUVENTUS'},
      {'keys': ['inter milan', 'inter'], 'label': 'INTER MILAN'},
      {'keys': ['ac milan', 'milan'], 'label': 'AC MILAN'},
      {'keys': ['as roma', 'roma'], 'label': 'ROMA'},
      {'keys': ['napoli'], 'label': 'NAPOLI'},
      {'keys': ['al nassr', 'al-nassr'], 'label': 'AL NASSR'},
      {'keys': ['al hilal', 'al-hilal'], 'label': 'AL HILAL'},
      {'keys': ['al ittihad', 'al-ittihad'], 'label': 'AL ITTIHAD'},
      {'keys': ['inter miami'], 'label': 'INTER MIAMI'},
      {'keys': ['đt anh', 'tuyển anh', 'england'], 'label': 'ĐT ANH'},
      {'keys': ['đt pháp', 'tuyển pháp', 'france'], 'label': 'ĐT PHÁP'},
      {'keys': ['đt đức', 'tuyển đức', 'germany'], 'label': 'ĐT ĐỨC'},
      {'keys': ['đt ý', 'tuyển ý', 'italy'], 'label': 'ĐT Ý'},
      {'keys': ['đt tây ban nha', 'tuyển tây ban nha', 'spain'], 'label': 'ĐT TÂY BAN NHA'},
      {'keys': ['đt bồ đào nha', 'tuyển bồ đào nha', 'portugal'], 'label': 'ĐT BỒ ĐÀO NHA'},
      {'keys': ['đt hà lan', 'tuyển hà lan', 'netherlands'], 'label': 'ĐT HÀ LAN'},
      {'keys': ['đt bỉ', 'tuyển bỉ', 'belgium'], 'label': 'ĐT BỈ'},
      {'keys': ['đt argentina', 'tuyển argentina', 'argentina'], 'label': 'ĐT ARGENTINA'},
      {'keys': ['đt brazil', 'tuyển brazil', 'brazil'], 'label': 'ĐT BRAZIL'},
      {'keys': ['đt nhật bản', 'tuyển nhật bản', 'japan'], 'label': 'ĐT NHẬT BẢN'},
      {'keys': ['đt hàn quốc', 'tuyển hàn quốc', 'korea'], 'label': 'ĐT HÀN QUỐC'},
      {'keys': ['đt ai cập', 'tuyển ai cập', 'ai cập', 'egypt'], 'label': 'ĐT AI CẬP'},
      {'keys': ['đt ma rốc', 'tuyển ma rốc', 'ma rốc', 'morocco'], 'label': 'ĐT MA RỐC'},
      {'keys': ['đt nam phi', 'nam phi', 'south africa'], 'label': 'ĐT NAM PHI'},
      {'keys': ['đt senegal', 'senegal'], 'label': 'ĐT SENEGAL'},
      {'keys': ['đt nigeria', 'nigeria'], 'label': 'ĐT NIGERIA'},
      {'keys': ['đt mali', 'mali'], 'label': 'ĐT MALI'},
    ];

    bool matchFavorite = isVn || isMu;
    String badgeText = '';

    if (isVn) {
      badgeText = 'BÓNG ĐÁ VIỆT NAM';
    } else if (isMu) {
      badgeText = 'MANCHESTER UNITED';
    } else {
      for (final item in favoriteKeywords) {
        final List<String> keys = List<String>.from(item['keys']);
        for (final k in keys) {
          if (allText.contains(k)) {
            matchFavorite = true;
            badgeText = item['label'];
            break;
          }
        }
        if (matchFavorite) break;
      }
      if (!matchFavorite) {
        if (RegExp(r'(^|\s)mc(\s|$)').hasMatch(allText)) {
          matchFavorite = true;
          badgeText = 'MAN CITY';
        }
      }
    }

    // Check Major / Famous Worldwide Leagues
    final List<String> majorLeagueKeywords = [
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

    bool isMajorLeague = false;
    if (!isLowerOrWomenLeague && !esportsDetected) {
      for (final lk in majorLeagueKeywords) {
        if (allText.contains(lk)) {
          isMajorLeague = true;
          break;
        }
      }
    }

    final bool isHotFromScraper = json['isHot'] == true;

    final bool isFamousMatch = !esportsDetected && !isLowerOrWomenLeague && (
        isHotFromScraper ||
        json['isFamous'] == true ||
        isVn ||
        isMu ||
        matchFavorite ||
        isMajorLeague
    );

    final bool isHotMatch = !esportsDetected && !isLowerOrWomenLeague && (
        isHotFromScraper ||
        matchFavorite ||
        isFamousMatch ||
        rawTitle.contains('🔥') ||
        rawTitle.toLowerCase().contains('tâm điểm')
    );

    final bool live = json['isLive'] == true ||
        rawTitle.contains('🟢') ||
        rawTitle.contains('🔴') ||
        time.toLowerCase().contains('đang diễn ra') ||
        time.toLowerCase().contains('trực tiếp');

    final int ts = json['matchTimestamp'] is int
        ? json['matchTimestamp']
        : (int.tryParse(json['matchTimestamp']?.toString() ?? '') ?? 0);

    return MatchModel(
      id: id,
      slug: slug,
      title: rawTitle,
      time: time,
      league: league,
      homeTeam: home,
      awayTeam: away,
      homeLogo: homeLogo,
      awayLogo: awayLogo,
      poster: json['poster'] ?? json['background'] ?? '',
      description: desc,
      isVietnam: isVn,
      isMuFavorite: isMu,
      isFavorite: matchFavorite,
      isFamous: isFamousMatch,
      isHot: isHotMatch,
      isEsports: esportsDetected,
      favoriteBadgeText: badgeText,
      isLive: live,
      matchTimestamp: ts,
    );
  }

  /// Parses match kickoff time into local DateTime.
  DateTime? get matchStartTime {
    // 1. Try parsing time string with date: e.g. "22:55 - 04.10" or "22:55 04/10"
    final regex = RegExp(r'(\d{1,2}):(\d{2})\s*[-/ ]\s*(\d{1,2})[\./-](\d{1,2})');
    final m = regex.firstMatch(time);
    if (m != null) {
      final hour = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      final day = int.parse(m.group(3)!);
      final month = int.parse(m.group(4)!);
      final now = DateTime.now();
      int year = now.year;
      if (now.month == 12 && month == 1) year++;
      return DateTime(year, month, day, hour, min);
    }

    // 2. Try parsing time string with only hour:minute: e.g. "22:55"
    final timeOnlyRegex = RegExp(r'(\d{1,2}):(\d{2})');
    final mTime = timeOnlyRegex.firstMatch(time);
    if (mTime != null) {
      final hour = int.parse(mTime.group(1)!);
      final min = int.parse(mTime.group(2)!);
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, hour, min);
    }

    // 3. Fallback to matchTimestamp
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

  /// Returns true if the match is currently ongoing (within 90 mins of kickoff, or live within 110 mins).
  bool get isOngoingNow {
    final elapsed = elapsedMinutes;
    if (elapsed == null) return isLive;
    // Between -5 min (countdown to kickoff) and 95 min (match in progress), or isLive up to 110 min
    if (elapsed >= -5 && elapsed <= (isLive ? 110 : 95)) {
      return true;
    }
    return false;
  }

  /// Returns true if the match started > 100-115 min ago (already finished / 2 tiếng trước)
  bool get isFinishedMatch {
    final elapsed = elapsedMinutes;
    if (elapsed == null) return false;
    return elapsed > (isLive ? 115 : 100);
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
}

class StreamChannel {
  final String name;
  final String title;
  final String url;
  final Map<String, String> headers;

  StreamChannel({
    required this.name,
    required this.title,
    required this.url,
    required this.headers,
  });

  factory StreamChannel.fromJson(Map<String, dynamic> json) {
    final Map<String, String> hdrs = {};
    if (json['behaviorHints'] != null &&
        json['behaviorHints']['proxyHeaders'] != null &&
        json['behaviorHints']['proxyHeaders']['request'] != null) {
      final reqHeaders = json['behaviorHints']['proxyHeaders']['request'] as Map<String, dynamic>;
      reqHeaders.forEach((k, v) {
        hdrs[k] = v.toString();
      });
    }

    return StreamChannel(
      name: json['name'] ?? 'Xôi Lạc TV',
      title: json['title'] ?? 'Kênh phát sóng (Full HD)',
      url: json['url'] ?? '',
      headers: hdrs,
    );
  }
}
