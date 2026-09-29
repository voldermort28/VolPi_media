import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/match_model.dart';
import '../models/anime_model.dart';
import '../models/movie_model.dart';
import '../models/iptv_channel_model.dart';

class ApiService {
  static const String defaultHost = 'https://stremio.laboon.vn';
  final String baseUrl;

  ApiService({this.baseUrl = defaultHost});

  // =========================================================================
  // 1. FOOTBALL / XÔI LẠC TV
  // =========================================================================

  /// Fetches live matches.
  /// If forceRefresh is true, appends timestamp query to bypass any client/CDN cache.
  Future<List<MatchModel>> getLiveMatches({bool forceRefresh = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // 1. Try direct /api/matches first (richest metadata & logo URLs)
    final apiUrl = '$baseUrl/api/matches?_t=$timestamp';
    try {
      final res = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is List && data.isNotEmpty) {
          final matches = data.map((item) => MatchModel.fromJson(item)).toList();
          _sortMatches(matches);
          return matches;
        }
      }
    } catch (_) {}

    // 2. Fallback to Stremio catalog endpoint
    final catalogUrl = forceRefresh
        ? '$baseUrl/xoilac/catalog/tv/xoilac-catalog.json?_t=$timestamp'
        : '$baseUrl/xoilac/catalog/tv/xoilac-catalog.json';

    try {
      final res = await http.get(Uri.parse(catalogUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['metas'] != null) {
          final List list = data['metas'];
          final matches = list.map((item) => MatchModel.fromJson(item)).toList();
          _sortMatches(matches);
          return matches;
        }
      }
    } catch (e) {
      // Log or handle error
    }
    return [];
  }

  void _sortMatches(List<MatchModel> matches) {
    // Sort: Việt Nam & MU #1, Favorite Clubs & Hot #2, Others #3
    matches.sort((a, b) {
      int scoreA = (a.isVietnam || a.isMuFavorite) ? 0 : (a.isFavorite ? 1 : 2);
      int scoreB = (b.isVietnam || b.isMuFavorite) ? 0 : (b.isFavorite ? 1 : 2);
      return scoreA.compareTo(scoreB);
    });
  }

  /// Fetches available stream channels (with BLV names and proxy headers) for a match.
  Future<List<StreamChannel>> getMatchStreams(String matchId) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = '$baseUrl/xoilac/stream/tv/$matchId.json?_t=$timestamp';

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['streams'] != null) {
          final List list = data['streams'];
          return list.map((item) => StreamChannel.fromJson(item)).toList();
        }
      }
    } catch (e) {
      // Log error
    }
    return [];
  }

  // =========================================================================
  // 2. YUMEI ANIME & TOKUSATSU
  // =========================================================================

  Future<List<AnimeModel>> getAnimeCatalog(String catalogId, {String? genre}) async {
    String url = '$baseUrl/catalog/series/$catalogId.json';
    if (genre != null && genre.isNotEmpty) {
      url = '$baseUrl/catalog/series/$catalogId/genre=${Uri.encodeComponent(genre)}.json';
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['metas'] != null) {
          final List list = data['metas'];
          return list.map((item) => AnimeModel.fromJson(item)).toList();
        }
      }
    } catch (e) {
      // Log error
    }
    return [];
  }

  Future<AnimeModel?> getAnimeDetails(String animeId, {String type = 'series'}) async {
    final url = '$baseUrl/meta/$type/$animeId.json';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['meta'] != null) {
          return AnimeModel.fromJson(data['meta']);
        }
      }
    } catch (e) {
      // Log error
    }
    return null;
  }

  Future<List<StreamChannel>> getAnimeEpisodeStreams(
    String animeId,
    int season,
    int episode, {
    String type = 'series',
  }) async {
    final String streamId = type == 'movie' ? animeId : '$animeId:$season:$episode';
    final url = '$baseUrl/stream/$type/$streamId.json';

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['streams'] != null && (data['streams'] as List).isNotEmpty) {
          final List list = data['streams'];
          return list
              .where((s) => s is Map && s['url'] != null && s['url'].toString().startsWith('http'))
              .map<StreamChannel>((s) => StreamChannel.fromJson(Map<String, dynamic>.from(s as Map)))
              .toList();
        }
      }
    } catch (e) {
      // Log error
    }
    return [];
  }

  Future<String?> getAnimeEpisodeStream(
    String animeId,
    int season,
    int episode, {
    String type = 'series',
    String? variant,
  }) async {
    final streams = await getAnimeEpisodeStreams(animeId, season, episode, type: type);
    if (streams.isEmpty) return null;

    if (variant != null) {
      final isSub = variant.toUpperCase() == 'SUB';
      final match = streams.firstWhere(
        (s) => isSub
            ? (s.title.toLowerCase().contains('phụ đề') || s.title.toLowerCase().contains('sub'))
            : (s.title.toLowerCase().contains('thuyết minh') || s.title.toLowerCase().contains('dub')),
        orElse: () => streams.first,
      );
      return match.url;
    }
    return streams.first.url;
  }

  // =========================================================================
  // 3. VLFILM / KHO PHIM BÍ MẬT (PROFILE PASSCODE 3105)
  // =========================================================================

  Future<List<MovieModel>> getVlxxCatalog({String? searchQuery, int skip = 0}) async {
    String url = skip > 0
        ? '$baseUrl/vlxx/catalog/movie/vlxx-catalog/skip=$skip.json'
        : '$baseUrl/vlxx/catalog/movie/vlxx-catalog.json';
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(searchQuery.trim());
      url = skip > 0
          ? '$baseUrl/vlxx/catalog/movie/vlxx-catalog/search=$encoded&skip=$skip.json'
          : '$baseUrl/vlxx/catalog/movie/vlxx-catalog/search=$encoded.json';
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['metas'] != null) {
          final List list = data['metas'];
          return list.map((item) => MovieModel.fromJson(item)).toList();
        }
      }
    } catch (e) {
      // Log error
    }
    return [];
  }

  /// Get direct master.m3u8 proxy URLs for VLFilm
  List<StreamChannel> getVlxxStreams(String rawId) {
    final cleanId = rawId.replaceFirst('vlxx:', '');
    return [
      StreamChannel(
        name: 'VLFilm',
        title: 'Server #1 (Full HD - Không quảng cáo)',
        url: '$baseUrl/hls/$cleanId/1/master.m3u8',
        headers: {},
      ),
      StreamChannel(
        name: 'VLFilm',
        title: 'Server #2 (Full HD - Không quảng cáo)',
        url: '$baseUrl/hls/$cleanId/2/master.m3u8',
        headers: {},
      ),
    ];
  }

  // =========================================================================
  // 4. IPTV / TRUYỀN HÌNH TRỰC TUYẾN
  // =========================================================================

  Future<List<IptvChannelModel>> getIptvChannels({bool forceRefresh = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = forceRefresh
        ? '$baseUrl/api/iptv/channels?_t=$timestamp'
        : '$baseUrl/api/iptv/channels';

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data
              .where((item) => item is Map<String, dynamic> || item is Map)
              .map<IptvChannelModel>((item) => IptvChannelModel.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      // Log error
    }
    return [];
  }

  Future<bool> refreshIptvSourceOnServer() async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/iptv/refresh')).timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

