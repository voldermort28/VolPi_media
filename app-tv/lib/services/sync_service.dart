import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'watch_history_service.dart';
import 'favorites_service.dart';

class SyncService with WidgetsBindingObserver {
  static final SyncService _lifecycleObserver = SyncService._();
  SyncService._();

  static const String _syncKey = '3105';
  static Timer? _pushDebounce;
  static Timer? _periodicPullTimer;
  static String? _configuredBaseUrl;
  static bool _listenersAttached = false;
  static bool _isAppForeground = true;
  static Future<void> _syncMutex = Future.value();
  static final http.Client _sharedClient = http.Client();

  /// Khởi tạo và thiết lập tự động đồng bộ 2 chiều (tự tạm dừng khi app ẩn nền)
  static void init(String baseUrl) {
    _configuredBaseUrl = baseUrl;
    if (!_listenersAttached) {
      _listenersAttached = true;
      WidgetsBinding.instance.addObserver(_lifecycleObserver);
      WatchHistoryService.instance.syncTriggerNotifier.addListener(_onDataChanged);
      FavoritesService.instance.syncTriggerNotifier.addListener(_onDataChanged);
    }

    syncFull(baseUrl);
    _startPeriodicPull();
  }

  static void _startPeriodicPull() {
    _periodicPullTimer?.cancel();
    _periodicPullTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_isAppForeground && _configuredBaseUrl != null) {
        pullFromServer(_configuredBaseUrl);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppForeground = true;
      _startPeriodicPull();
      if (_configuredBaseUrl != null) {
        pullFromServer(_configuredBaseUrl);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _isAppForeground = false;
      _periodicPullTimer?.cancel();
      WatchHistoryService.instance.flush();
      FavoritesService.instance.flush();
    }
  }

  static void _onDataChanged() {
    if (_configuredBaseUrl != null) {
      schedulePush(_configuredBaseUrl!);
    }
  }

  /// Xếp hàng thực thi tuần tự các tác vụ đồng bộ (chống race condition giữa pull & push)
  static Future<void> _enqueue(Future<void> Function() task) {
    _syncMutex = _syncMutex.then((_) => task()).catchError((_) {});
    return _syncMutex;
  }

  /// Đồng bộ đầy đủ 2 chiều: Kéo dữ liệu từ server về trước, sau đó đẩy dữ liệu cục bộ lên
  static Future<void> syncFull(String baseUrl, {http.Client? client}) {
    return _enqueue(() async {
      await _pullInternal(baseUrl, client: client);
      await _pushInternal(baseUrl, client: client);
    });
  }

  static Future<void> pullFromServer(String? baseUrl, {http.Client? client}) {
    final targetUrl = baseUrl ?? _configuredBaseUrl;
    if (targetUrl == null) return Future.value();
    return _enqueue(() => _pullInternal(targetUrl, client: client));
  }

  static Future<void> pushToServer(String? baseUrl, {http.Client? client}) {
    final targetUrl = baseUrl ?? _configuredBaseUrl;
    if (targetUrl == null) return Future.value();
    return _enqueue(() => _pushInternal(targetUrl, client: client));
  }

  static void schedulePush(String? baseUrl, {http.Client? client}) {
    final targetUrl = baseUrl ?? _configuredBaseUrl;
    if (targetUrl == null) return;
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 3), () {
      pushToServer(targetUrl, client: client);
    });
  }

  static Future<void> _pullInternal(String targetUrl, {http.Client? client}) async {
    final httpClient = client ?? _sharedClient;
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
              List<Map<String, dynamic>>.from(
                (data['history'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
              ),
            );
          }
          if (data['favorites'] is List) {
            FavoritesService.instance.importFromSync(
              List<Map<String, dynamic>>.from(
                (data['favorites'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('SyncService.pullFromServer failed: $e');
    }
  }

  static Future<void> _pushInternal(String targetUrl, {http.Client? client}) async {
    final httpClient = client ?? _sharedClient;
    try {
      // Loại bỏ hoàn toàn mục riêng tư (category: 'secret') khỏi luồng đồng bộ công khai
      final historyPayload = WatchHistoryService.instance.exportForSync(excludeCategory: 'secret');
      final favoritesPayload = FavoritesService.instance.exportForSync(excludeCategory: 'secret');
      final sentDeletedFavIds = List<String>.from(FavoritesService.instance.pendingDeletions);
      final sentDeletedHistoryIds = List<String>.from(WatchHistoryService.instance.pendingDeletions);

      final body = {
        'key': _syncKey,
        'history': historyPayload,
        'favorites': favoritesPayload,
        'deletedFavoriteIds': sentDeletedFavIds,
        'deletedHistoryIds': sentDeletedHistoryIds,
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
        // Chỉ xóa đúng snapshot các ID đã được gửi thành công lên server
        WatchHistoryService.instance.removePendingDeletions(sentDeletedHistoryIds);
        FavoritesService.instance.removePendingDeletions(sentDeletedFavIds);

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
              List<Map<String, dynamic>>.from(
                (merged['history'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
              ),
            );
          }
          if (merged['favorites'] is List) {
            FavoritesService.instance.importFromSync(
              List<Map<String, dynamic>>.from(
                (merged['favorites'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('SyncService.pushToServer failed: $e');
    }
  }
}
