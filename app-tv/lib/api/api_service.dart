import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/match_model.dart';
export '../models/match_model.dart';
import '../models/anime_model.dart';
import '../models/movie_model.dart';
import '../models/iptv_channel_model.dart';
import '../models/gdrive_model.dart';
import '../models/telegram_model.dart';

class ApiService {
  static const String defaultHost = 'https://stremio.laboon.vn';
  final String baseUrl;
  final http.Client _client;

  ApiService({this.baseUrl = defaultHost, http.Client? client}) : _client = client ?? http.Client();

  http.Client get client => _client;

  void dispose() {
    _client.close();
  }

  // =========================================================================
  // =========================================================================
  // 1. FOOTBALL / XÔI LẠC TV & SOCOLIVE TV
  // =========================================================================

  /// Fetches live matches.
  /// If forceRefresh is true, appends timestamp query to bypass any client/CDN cache.
  /// source can be 'xoilac', 'socolive', 'gavang', or 'vebo'.
  Future<List<MatchModel>> getLiveMatches({bool forceRefresh = false, String source = 'xoilac'}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final src = source.toLowerCase();

    // 1. Try direct API endpoint first (richest metadata & logo URLs)
    String apiUrl = '$baseUrl/api/matches?_t=$timestamp';
    if (src == 'gavang') {
      apiUrl = '$baseUrl/api/gavang/matches?_t=$timestamp';
    } else if (src == 'vebo') {
      apiUrl = '$baseUrl/api/vebo/matches?_t=$timestamp';
    } else if (src == 'socolive') {
      apiUrl = '$baseUrl/api/socolive/matches?_t=$timestamp';
    }

    try {
      final res = await _client.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is List && data.isNotEmpty) {
          final matches = data.map((item) => MatchModel.fromJson(item)).toList();
          MatchModel.sortByPriority(matches);
          return matches;
        }
      }
    } catch (_) {}

    // 2. Fallback to Stremio catalog endpoint
    String catalogPath = 'xoilac/catalog/tv/xoilac-catalog.json';
    if (src == 'socolive') {
      catalogPath = 'socolive/catalog/tv/socolive-catalog.json';
    }
    final catalogUrl = forceRefresh
        ? '$baseUrl/$catalogPath?_t=$timestamp'
        : '$baseUrl/$catalogPath';

    try {
      final res = await _client.get(Uri.parse(catalogUrl)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data['metas'] != null) {
          final List list = data['metas'];
          final matches = list.map((item) => MatchModel.fromJson(item)).toList();
          MatchModel.sortByPriority(matches);
          return matches;
        }
      }
    } catch (e) {
      // Log or handle error
    }
    return [];
  }

  void _sortMatches(List<MatchModel> matches) {
    MatchModel.sortByPriority(matches);
  }

  /// Fetches available stream channels (with BLV names and proxy headers) for a match.
  Future<List<StreamChannel>> getMatchStreams(String matchId, {String? source}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final isGavang = matchId.startsWith('gavang:') || (source != null && source.toLowerCase() == 'gavang');
    final isVebo = matchId.startsWith('vebo:') || (source != null && source.toLowerCase() == 'vebo');
    final isSoco = matchId.startsWith('socolive:') || (source != null && source.toLowerCase() == 'socolive');

    // 1. Direct REST stream endpoints for Gà Vàng & Về Bờ
    if (isGavang) {
      final directUrl = '$baseUrl/api/gavang/streams/$matchId?_t=$timestamp';
      try {
        final res = await _client.get(Uri.parse(directUrl)).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = json.decode(utf8.decode(res.bodyBytes));
          if (data['streams'] != null && data['streams'] is List) {
            final List list = data['streams'];
            if (list.isNotEmpty) {
              return list.map((item) => StreamChannel.fromJson(item)).toList();
            }
          }
        }
      } catch (_) {}
    }

    if (isVebo) {
      final directUrl = '$baseUrl/api/vebo/streams/$matchId?_t=$timestamp';
      try {
        final res = await _client.get(Uri.parse(directUrl)).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = json.decode(utf8.decode(res.bodyBytes));
          if (data['streams'] != null && data['streams'] is List) {
            final List list = data['streams'];
            if (list.isNotEmpty) {
              return list.map((item) => StreamChannel.fromJson(item)).toList();
            }
          }
        }
      } catch (_) {}
    }

    // 2. Standard Stremio stream endpoint fallback
    String streamPath = 'xoilac/stream/tv';
    if (isGavang || isVebo) {
      streamPath = 'stream/tv';
    } else if (isSoco) {
      streamPath = 'socolive/stream/tv';
    }
    final url = '$baseUrl/$streamPath/$matchId.json?_t=$timestamp';

    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
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
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
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
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
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
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
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

  Future<List<MovieModel>> getVlxxCatalog({String? searchQuery, int skip = 0, String? genre}) async {
    String url = skip > 0
        ? '$baseUrl/vlxx/catalog/movie/vlxx-catalog/skip=$skip.json'
        : '$baseUrl/vlxx/catalog/movie/vlxx-catalog.json';
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(searchQuery.trim());
      url = skip > 0
          ? '$baseUrl/vlxx/catalog/movie/vlxx-catalog/search=$encoded&skip=$skip.json'
          : '$baseUrl/vlxx/catalog/movie/vlxx-catalog/search=$encoded.json';
    } else if (genre != null && genre.isNotEmpty && genre != 'Tất cả') {
      final encodedGenre = Uri.encodeComponent(genre);
      url = skip > 0
          ? '$baseUrl/vlxx/catalog/movie/vlxx-catalog/genre=$encodedGenre&skip=$skip.json'
          : '$baseUrl/vlxx/catalog/movie/vlxx-catalog/genre=$encodedGenre.json';
    }

    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
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
  // 3.1 VIET69 / KHO PHIM RIÊNG TƯ (TAB MỚI)
  // =========================================================================

  Future<List<MovieModel>> getViet69Catalog({String? searchQuery, int skip = 0, String? genre}) async {
    String url = skip > 0
        ? '$baseUrl/viet69/catalog/movie/viet69-catalog/skip=$skip.json'
        : '$baseUrl/viet69/catalog/movie/viet69-catalog.json';
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(searchQuery.trim());
      url = skip > 0
          ? '$baseUrl/viet69/catalog/movie/viet69-catalog/search=$encoded&skip=$skip.json'
          : '$baseUrl/viet69/catalog/movie/viet69-catalog/search=$encoded.json';
    } else if (genre != null && genre.isNotEmpty && genre != 'Tất cả') {
      final encodedGenre = Uri.encodeComponent(genre);
      url = skip > 0
          ? '$baseUrl/viet69/catalog/movie/viet69-catalog/genre=$encodedGenre&skip=$skip.json'
          : '$baseUrl/viet69/catalog/movie/viet69-catalog/genre=$encodedGenre.json';
    }

    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
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

  /// Get direct master.m3u8 proxy URLs for Viet69
  List<StreamChannel> getViet69Streams(String rawId) {
    final cleanId = rawId.replaceFirst('viet69:', '');
    return [
      StreamChannel(
        name: 'Viet69',
        title: 'Server #2 (Full HD M3U8 - Không quảng cáo)',
        url: '$baseUrl/viet69/hls/$cleanId/2/master.m3u8',
        headers: {},
      ),
      StreamChannel(
        name: 'Viet69',
        title: 'Server #1 (Full HD - Không quảng cáo)',
        url: '$baseUrl/viet69/hls/$cleanId/1/master.m3u8',
        headers: {},
      ),
    ];
  }

  // =========================================================================
  // 3.2 XNHAU / KHO PHIM RIÊNG TƯ MỚI (TAB XNHAU)
  // =========================================================================

  Future<List<MovieModel>> getXnhauCatalog({String? searchQuery, int skip = 0, String? genre}) async {
    String url = skip > 0
        ? '$baseUrl/xnhau/catalog/movie/xnhau-catalog/skip=$skip.json'
        : '$baseUrl/xnhau/catalog/movie/xnhau-catalog.json';
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final encoded = Uri.encodeComponent(searchQuery.trim());
      url = skip > 0
          ? '$baseUrl/xnhau/catalog/movie/xnhau-catalog/search=$encoded&skip=$skip.json'
          : '$baseUrl/xnhau/catalog/movie/xnhau-catalog/search=$encoded.json';
    } else if (genre != null && genre.isNotEmpty && genre != 'Tất cả') {
      final encodedGenre = Uri.encodeComponent(genre);
      url = skip > 0
          ? '$baseUrl/xnhau/catalog/movie/xnhau-catalog/genre=$encodedGenre&skip=$skip.json'
          : '$baseUrl/xnhau/catalog/movie/xnhau-catalog/genre=$encodedGenre.json';
    }

    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
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

  /// Get direct MP4 stream URLs for xNhau
  List<StreamChannel> getXnhauStreams(String rawId) {
    final cleanId = rawId.replaceFirst('xnhau:', '');
    return [
      StreamChannel(
        name: 'xNhau',
        title: 'Server #1 (Full HD - Trực tiếp)',
        url: '$baseUrl/xnhau/stream/$cleanId/1.mp4',
        headers: {},
      ),
      StreamChannel(
        name: 'xNhau',
        title: 'Server #2 (Chuẩn SD - Dự phòng)',
        url: '$baseUrl/xnhau/stream/$cleanId/2.mp4',
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
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
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

  Future<List<IptvSourceModel>> getIptvSources() async {
    final url = '$baseUrl/api/iptv/sources';
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data
              .where((item) => item is Map<String, dynamic> || item is Map)
              .map<IptvSourceModel>((item) => IptvSourceModel.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (_) {
      // Log error
    }
    return [];
  }

  Future<bool> refreshIptvSourceOnServer() async {
    try {
      final res = await _client.post(Uri.parse('$baseUrl/api/iptv/refresh')).timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // 5. GOOGLE DRIVE (PUBLIC & PRIVATE FOLDERS)
  // =========================================================================

  /// Fetch configured Google Drive sources from server (optional filter by isPrivate)
  Future<List<GDriveSourceModel>> getGDriveSources({bool? isPrivate, bool forceRefresh = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String url = '$baseUrl/api/gdrive/sources?_t=$timestamp';
    if (isPrivate != null) {
      url += '&isPrivate=$isPrivate';
    }
    if (forceRefresh) {
      url += '&forceRefresh=true';
    }
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data
              .where((item) => item is Map<String, dynamic> || item is Map)
              .map<GDriveSourceModel>((item) => GDriveSourceModel.fromJson(Map<String, dynamic>.from(item as Map)))
              .where((s) => s.enabled)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetch folder contents (subfolders + video files)
  Future<GDriveFolderContentResult?> getGDriveFolderContents(String folderId, {bool forceRefresh = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = forceRefresh
        ? '$baseUrl/api/gdrive/folders/$folderId?forceRefresh=true&_t=$timestamp'
        : '$baseUrl/api/gdrive/folders/$folderId';
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is Map<String, dynamic> || data is Map) {
          return GDriveFolderContentResult.fromJson(Map<String, dynamic>.from(data as Map));
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get direct stream URL with Range (HTTP 206) proxy support
  String getGDriveStreamUrl(String fileId, {String? fileName}) {
    if (fileName != null && fileName.trim().isNotEmpty) {
      final safeName = Uri.encodeComponent(fileName.trim());
      return '$baseUrl/api/gdrive/stream/$fileId/$safeName';
    }
    return '$baseUrl/api/gdrive/stream/$fileId';
  }

  /// Get subtitle URL
  String getGDriveSubtitleUrl(String subtitleFileId) {
    return '$baseUrl/api/gdrive/subtitle/$subtitleFileId';
  }

  // =========================================================================
  // 6. TELEGRAM CHANNELS & VIDEOS
  // =========================================================================

  /// Fetch all configured Telegram sources from server
  Future<List<TelegramSourceModel>> getTelegramSources({bool forceRefresh = false}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = forceRefresh ? '$baseUrl/api/telegram/sources?_t=$timestamp' : '$baseUrl/api/telegram/sources';
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is List) {
          return data
              .where((item) => item is Map<String, dynamic> || item is Map)
              .map<TelegramSourceModel>((item) => TelegramSourceModel.fromJson(Map<String, dynamic>.from(item as Map)))
              .where((s) => s.enabled)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetch video messages from a Telegram channel
  Future<TelegramChannelVideosResult?> getTelegramVideos(String channelId, {bool forceRefresh = false, int limit = 2500}) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final encodedId = Uri.encodeComponent(channelId);
    final url = forceRefresh
        ? '$baseUrl/api/telegram/channels/$encodedId/videos?forceRefresh=true&limit=$limit&_t=$timestamp'
        : '$baseUrl/api/telegram/channels/$encodedId/videos?limit=$limit';
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        if (data is Map<String, dynamic> || data is Map) {
          return TelegramChannelVideosResult.fromJson(Map<String, dynamic>.from(data as Map));
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get direct video stream URL with Range (HTTP 206) MTProto chunk proxy
  String getTelegramStreamUrl(String channelId, int messageId) {
    final encodedId = Uri.encodeComponent(channelId);
    return '$baseUrl/api/telegram/stream/$encodedId/$messageId';
  }

  /// Get video thumbnail URL from Telegram
  String getTelegramThumbUrl(String channelId, int messageId) {
    final encodedId = Uri.encodeComponent(channelId);
    return '$baseUrl/api/telegram/thumb/$encodedId/$messageId';
  }
}

