import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'watch_history_service.dart';
import 'favorites_service.dart';

class SyncService {
  static const String _syncKey = '3105'; // Mã đồng bộ mặc định (PIN chung)
  static Timer? _pushDebounce;
  static bool _isSyncing = false;

  /// Gọi khi app khởi động để lấy dữ liệu mới nhất từ các thiết bị khác về
  static Future<void> pullFromServer(String baseUrl, {http.Client? client}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    final httpClient = client ?? http.Client();
    try {
      final url = Uri.parse('$baseUrl/api/user/sync?key=$_syncKey&_t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await httpClient.get(url).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        if (body is Map && body['success'] == true && body['data'] is Map) {
          final data = body['data'];
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
  static void schedulePush(String baseUrl, {http.Client? client}) {
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 3), () {
      pushToServer(baseUrl, client: client);
    });
  }

  /// Gửi dữ liệu cục bộ lên server để hợp nhất và chia sẻ với các thiết bị khác
  static Future<void> pushToServer(String baseUrl, {http.Client? client}) async {
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

      final url = Uri.parse('$baseUrl/api/user/sync');
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
