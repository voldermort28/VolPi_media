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
  final bool isMuFavorite;
  final bool isHot;

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
    this.isMuFavorite = false,
    this.isHot = false,
  });

  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final String rawTitle = json['name'] ?? json['title'] ?? '';
    final String desc = json['description'] ?? '';
    final String id = json['id'] ?? '';
    final String slug = id.replaceFirst('xoilac:', '');

    final bool isMu = rawTitle.contains('⭐') ||
        rawTitle.toLowerCase().contains('manchester united') ||
        rawTitle.toLowerCase().contains('mu ') ||
        rawTitle.toLowerCase().contains('man utd');

    final bool isHotMatch = rawTitle.contains('🔥') ||
        rawTitle.toLowerCase().contains('tâm điểm') ||
        rawTitle.toLowerCase().contains('real madrid') ||
        rawTitle.toLowerCase().contains('barcelona') ||
        rawTitle.toLowerCase().contains('arsenal') ||
        rawTitle.toLowerCase().contains('chelsea') ||
        rawTitle.toLowerCase().contains('liverpool') ||
        rawTitle.toLowerCase().contains('man city');

    // Extract league & time if present in description
    String league = 'Bóng đá';
    String time = 'Đang diễn ra';
    String home = 'Đội nhà';
    String away = 'Đội khách';

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
      isMuFavorite: isMu,
      isHot: isHotMatch,
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
