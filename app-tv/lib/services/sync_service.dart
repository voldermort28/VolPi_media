import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'watch_history_service.dart';
import 'favorites_service.dart';

class SyncService {
  static const String _syncKey = '3105'; // Mã đồng bộ mặc định (PIN chung)
  static Timer? _pushDebounce;
  static Timer? _periodicPullTimer;
  static bool _isSyncing = false;
  static String? _configuredBaseUrl;
  static bool _listenersAttached = false;

  /// Khởi tạo và thiết lập tự động đồng bộ 2 chiều
  static void init(String baseUrl) {
    _configuredBaseUrl = baseUrl;
    if (!_listenersAttached) {
      _listenersAttached = true;
      WatchHistoryService.instance.changeNotifier.addListener(_onDataChanged);
      FavoritesService.instance.changeNotifier.addListener(_onDataChanged);
    }
    // Thực hiện đồng bộ 2 chiều ngay khi khởi động
    syncFull(baseUrl);

    // Tự động kéo dữ liệu đồng bộ từ server mỗi 15 giây để cập nhật tức thì giữa các thiết bị
    _periodicPullTimer?.cancel();
    _periodicPullTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      pullFromServer(null);
    });
  }

  static void _onDataChanged() {
    if (_configuredBaseUrl != null && !_isSyncing) {
      schedulePush(_configuredBaseUrl!);
    }
  }

  /// Đồng bộ đầy đủ 2 chiều: Kéo dữ liệu từ server về trước, sau đó đẩy dữ liệu cục bộ lên
  static Future<void> syncFull(String baseUrl, {http.Client? client}) async {
    await pullFromServer(baseUrl, client: client);
    await pushToServer(baseUrl, client: client);
  }

  /// Gọi khi app khởi động để lấy dữ liệu mới nhất từ các thiết bị khác về
  static Future<void> pullFromServer(String? baseUrl, {http.Client? client}) async {
    final targetUrl = baseUrl ?? _configuredBaseUrl;
    if (targetUrl == null || _isSyncing) return;
    _isSyncing = true;
    final httpClient = client ?? http.Client();
    try {
      final url = Uri.parse('$targetUrl/api/user/sync?key=$_syncKey&_t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await httpClient.get(url).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['success'] == true && body['data'] is Map) {
          final data = body['data'];
          if (data['deletedFavoriteIds'] is List) {
            for (final id in data['deletedFavoriteIds']) {
              FavoritesService.instance.removeLocalOnly(id.toString());
            }
          }
          if (data['deletedHistoryIds'] is List) {
            for (final id in data['deletedHistoryIds']) {
              WatchHistoryService.instance.removeLocalOnly(id.toString());
            }
          }
          if (data['history'] is List) {
            WatchHistoryService.instance.importFromSync(
              List<Map<String, dynamic>>.from(data['history']),
            );
          }
          if (data['favorites'] is List) {
            FavoritesService.instance.importFromSync(
              List<Map<String, dynamic>>.from(data['favorites']),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('SyncService.pullFromServer failed (offline or network): $e');
    } finally {
      if (client == null) httpClient.close();
      _isSyncing = false;
    }
  }

  /// Gom các thay đổi để đồng bộ lên server sau 3 giây (debounce)
  static void schedulePush(String? baseUrl, {http.Client? client}) {
    final targetUrl = baseUrl ?? _configuredBaseUrl;
    if (targetUrl == null) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 3), () {
      pushToServer(targetUrl, client: client);
    });
  }

  /// Gửi dữ liệu cục bộ lên server để hợp nhất và chia sẻ với các thiết bị khác
  static Future<void> pushToServer(String? baseUrl, {http.Client? client}) async {
    final targetUrl = baseUrl ?? _configuredBaseUrl;
    if (targetUrl == null) return;
    final httpClient = client ?? http.Client();
    try {
      final historyPayload = WatchHistoryService.instance.exportForSync();
      final favoritesPayload = FavoritesService.instance.exportForSync();
      final deletedFavIds = FavoritesService.instance.pendingDeletions;
      final deletedHistoryIds = WatchHistoryService.instance.pendingDeletions;

      final body = {
        'key': _syncKey,
        'history': historyPayload,
        'favorites': favoritesPayload,
        'deletedFavoriteIds': deletedFavIds,
        'deletedHistoryIds': deletedHistoryIds,
      };

      final url = Uri.parse('$targetUrl/api/user/sync');
      final res = await httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final resBody = jsonDecode(utf8.decode(res.bodyBytes));
        if (resBody is Map && resBody['success'] == true && resBody['data'] is Map) {
          final merged = resBody['data'];
          if (merged['deletedFavoriteIds'] is List) {
            for (final id in merged['deletedFavoriteIds']) {
              FavoritesService.instance.removeLocalOnly(id.toString());
            }
          }
          if (merged['deletedHistoryIds'] is List) {
            for (final id in merged['deletedHistoryIds']) {
              WatchHistoryService.instance.removeLocalOnly(id.toString());
            }
          }
          if (merged['history'] is List) {
            WatchHistoryService.instance.importFromSync(
              List<Map<String, dynamic>>.from(merged['history']),
            );
            WatchHistoryService.instance.clearPendingDeletions();
          }
          if (merged['favorites'] is List) {
            FavoritesService.instance.importFromSync(
              List<Map<String, dynamic>>.from(merged['favorites']),
            );
            FavoritesService.instance.clearPendingDeletions();
          }
        }
      }
    } catch (e) {
      debugPrint('SyncService.pushToServer failed (offline or network): $e');
    } finally {
      if (client == null) httpClient.close();
    }
  }
}
