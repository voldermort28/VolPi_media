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
  final bool isHot;
  final String favoriteBadgeText;

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
    this.isHot = false,
    this.favoriteBadgeText = '',
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
    if (home.isEmpty) home = 'Đội nhà';
    if (away.isEmpty) away = 'Đội khách';

    final String allText = '$rawTitle $desc $home $away'.toLowerCase();

    // Check Vietnam
    final bool isVn = rawTitle.contains('⭐ [VIỆT NAM]') ||
        allText.contains('việt nam') ||
        allText.contains('viet nam') ||
        allText.contains('vietnam') ||
        allText.contains('u23 việt nam') ||
        allText.contains('đt việt nam');

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
      {'keys': ['brighton'], 'label': 'BRIGHTON'},
      {'keys': ['brentford'], 'label': 'BRENTFORD'},
      {'keys': ['real madrid'], 'label': 'REAL MADRID'},
      {'keys': ['barcelona', 'barca'], 'label': 'BARCELONA'},
      {'keys': ['bayern munich', 'bayern'], 'label': 'BAYERN MUNICH'},
      {'keys': ['paris saint-germain', 'psg', 'paris sg'], 'label': 'PSG'},
      {'keys': ['juventus', 'juve'], 'label': 'JUVENTUS'},
      {'keys': ['inter milan', 'inter'], 'label': 'INTER MILAN'},
      {'keys': ['ac milan', 'milan'], 'label': 'AC MILAN'},
      {'keys': ['dortmund', 'bvb'], 'label': 'DORTMUND'},
      {'keys': ['atletico madrid', 'atletico'], 'label': 'ATLETICO'},
      {'keys': ['leverkusen', 'bayer leverkusen'], 'label': 'LEVERKUSEN'},
    ];

    bool matchFavorite = isVn || isMu;
    String badgeText = '';

    if (isVn) {
      badgeText = 'ĐỘI TUYỂN VIỆT NAM';
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

    final bool isHotMatch = matchFavorite ||
        rawTitle.contains('🔥') ||
        rawTitle.toLowerCase().contains('tâm điểm');

    return MatchModel(
      id: id,
      slug: slug,
      title: rawTitle,
      time: time,
      league: league,
      homeTeam: home,
      awayTeam: away,
      homeLogo: json['homeLogo'] ?? '',
      awayLogo: json['awayLogo'] ?? '',
      poster: json['poster'] ?? json['background'] ?? '',
      description: desc,
      isVietnam: isVn,
      isMuFavorite: isMu,
      isFavorite: matchFavorite,
      isHot: isHotMatch,
      favoriteBadgeText: badgeText,
    );
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
