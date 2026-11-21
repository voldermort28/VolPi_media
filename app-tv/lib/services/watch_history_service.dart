import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/watch_history_model.dart';

class WatchHistoryService {
  static final WatchHistoryService _instance = WatchHistoryService._();
  static WatchHistoryService get instance => _instance;
  WatchHistoryService._();

  final Map<String, WatchHistoryItem> _cache = {};
  Timer? _writeDebounce;
  Future<void> _writeQueue = Future.value();
  static const int _maxItems = 200;
  bool _isInitialized = false;

  /// ValueNotifier cập nhật UI ngay lập tức
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// ValueNotifier riêng để kích hoạt đồng bộ lên server (không bắn bão HTTP mỗi 5s khi đang xem phim)
  final ValueNotifier<int> syncTriggerNotifier = ValueNotifier<int>(0);

  /// Danh sách các ID đã bị người dùng xóa, được lưu xuống đĩa để không bị mất khi tắt app
  final Set<String> _pendingDeletions = {};
  List<String> get pendingDeletions => _pendingDeletions.toList();

  void clearPendingDeletions() {
    if (_pendingDeletions.isNotEmpty) {
      _pendingDeletions.clear();
      _scheduleDiskWrite();
    }
  }

  void removePendingDeletions(Iterable<String> ids) {
    bool changed = false;
    for (final id in ids) {
      if (_pendingDeletions.remove(id)) changed = true;
    }
    if (changed) _scheduleDiskWrite();
  }

  /// Khởi tạo và nạp toàn bộ lịch sử + danh sách xóa chờ đồng bộ từ file JSON vào RAM
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_watch_history.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map) {
            if (data['pendingDeletions'] is List) {
              for (final id in data['pendingDeletions']) {
                if (id != null && id.toString().isNotEmpty) {
                  _pendingDeletions.add(id.toString());
                }
              }
            }
            if (data['items'] is List) {
              for (final raw in data['items']) {
                if (raw is Map<String, dynamic>) {
                  final item = WatchHistoryItem.fromJson(raw);
                  if (item.id.isNotEmpty && !_pendingDeletions.contains(item.id)) {
                    _cache[item.id] = item;
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('WatchHistoryService.init error: $e');
    } finally {
      _isInitialized = true;
      _notifyUi();
    }
  }

  WatchHistoryItem? getProgress(String id) => _cache[id];

  WatchHistoryItem? getLatestProgressForMedia(String mediaId) {
    final matches = _cache.values.where((item) =>
      item.mediaId == mediaId ||
      item.id == mediaId ||
      item.id.startsWith('anime:$mediaId:') ||
      item.id.startsWith('$mediaId:')
    ).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.first;
  }

  List<WatchHistoryItem> getContinueWatching({String? excludeCategory, String? category}) {
    return _cache.values
        .where((item) {
          if (!item.isInProgress) return false;
          if (category != null && item.category != category) return false;
          if (excludeCategory != null) {
            if (item.category == excludeCategory) return false;
            if (excludeCategory == 'secret' && WatchHistoryItem.isSecretOrPrivateItem(item.id, item.category)) {
              return false;
            }
          }
          return true;
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<WatchHistoryItem> getHistory({String? category, String? excludeCategory}) {
    return _cache.values
        .where((item) {
          if (category != null && item.category != category) return false;
          if (excludeCategory != null) {
            if (item.category == excludeCategory) return false;
            if (excludeCategory == 'secret' && WatchHistoryItem.isSecretOrPrivateItem(item.id, item.category)) {
              return false;
            }
          }
          return true;
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Lưu tiến trình xem — cập nhật RAM tức thì, gom ghi đĩa mỗi 4 giây.
  /// Đặt `triggerSync: false` cho các tick định kỳ 5s trong lúc đang xem để tránh bão HTTP POST.
  void saveProgress(WatchHistoryItem item, {bool triggerSync = true}) {
    _cache[item.id] = item;
    _pendingDeletions.remove(item.id);
    _enforceLimit();
    _notifyUi();
    if (triggerSync && !WatchHistoryItem.isSecretOrPrivateItem(item.id, item.category)) {
      _notifySync();
    }
    _scheduleDiskWrite();
  }

  void clearProgress(String id) {
    final removed = _cache.remove(id);
    if (removed != null) {
      if (!WatchHistoryItem.isSecretOrPrivateItem(id, removed.category)) {
        _pendingDeletions.add(id);
        _notifySync();
      }
      _notifyUi();
      _scheduleDiskWrite();
    }
  }

  void removeLocalOnly(String id) {
    if (_cache.containsKey(id)) {
      _cache.remove(id);
      _notifyUi();
      _scheduleDiskWrite();
    }
  }

  bool hasProgressForPrefix(String prefix) {
    return _cache.keys.any((k) => k == prefix || k.startsWith('$prefix:'));
  }

  void clearProgressForPrefix(String prefix) {
    final keysToRemove = _cache.keys.where((k) => k == prefix || k.startsWith('$prefix:')).toList();
    bool shouldSync = false;
    for (final k in keysToRemove) {
      final removed = _cache.remove(k);
      if (removed != null && !WatchHistoryItem.isSecretOrPrivateItem(k, removed.category)) {
        _pendingDeletions.add(k);
        shouldSync = true;
      }
    }
    if (keysToRemove.isNotEmpty) {
      _notifyUi();
      if (shouldSync) _notifySync();
      _scheduleDiskWrite();
    }
  }

  void clearAll({String? category}) {
    bool shouldSync = false;
    if (category == null) {
      for (final entry in _cache.entries) {
        if (!WatchHistoryItem.isSecretOrPrivateItem(entry.key, entry.value.category)) {
          _pendingDeletions.add(entry.key);
          shouldSync = true;
        }
      }
      _cache.clear();
    } else {
      final toRemove = _cache.values.where((i) => i.category == category).toList();
      for (final item in toRemove) {
        _cache.remove(item.id);
        if (!WatchHistoryItem.isSecretOrPrivateItem(item.id, item.category)) {
          _pendingDeletions.add(item.id);
          shouldSync = true;
        }
      }
    }
    _notifyUi();
    if (shouldSync) _notifySync();
    _scheduleDiskWrite();
  }

  void _enforceLimit() {
    if (_cache.length > _maxItems) {
      final sorted = _cache.values.toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (int i = 0; i < sorted.length - _maxItems; i++) {
        _cache.remove(sorted[i].id);
      }
    }
  }

  void _notifyUi() {
    changeNotifier.value++;
  }

  void _notifySync() {
    syncTriggerNotifier.value++;
  }

  void _scheduleDiskWrite() {
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(seconds: 4), () {
      _enqueueDiskWrite();
    });
  }

  Future<void> _enqueueDiskWrite() {
    _writeQueue = _writeQueue.then((_) => _writeToDisk()).catchError((_) {});
    return _writeQueue;
  }

  Future<void> _writeToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_watch_history.json');
      final tmpFile = File('${dir.path}/volpi_watch_history.json.tmp');
      final data = {
        'items': _cache.values.map((i) => i.toJson()).toList(),
        'pendingDeletions': _pendingDeletions.toList(),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await tmpFile.writeAsString(jsonEncode(data), flush: true);
      await tmpFile.rename(file.path);
    } catch (e) {
      debugPrint('WatchHistoryService._writeToDisk error: $e');
    }
  }

  Future<void> flush({bool triggerSync = false}) async {
    _writeDebounce?.cancel();
    await _enqueueDiskWrite();
    if (triggerSync) _notifySync();
  }

  List<Map<String, dynamic>> exportForSync({String? excludeCategory = 'secret'}) {
    return _cache.values
        .where((i) {
          if (excludeCategory == null) return true;
          if (i.category == excludeCategory) return false;
          if (excludeCategory == 'secret' && WatchHistoryItem.isSecretOrPrivateItem(i.id, i.category)) {
            return false;
          }
          return true;
        })
        .map((i) => i.toJson())
        .toList();
  }

  /// Nạp dữ liệu đồng bộ từ server, hợp nhất theo updatedAt và tuyệt đối bỏ qua các mục đang chờ xóa cục bộ
  void importFromSync(List<Map<String, dynamic>> items) {
    bool hasChange = false;
    for (final raw in items) {
      try {
        final incoming = WatchHistoryItem.fromJson(raw);
        if (incoming.id.isEmpty) continue;
        if (_pendingDeletions.contains(incoming.id)) continue;
        final existing = _cache[incoming.id];
        if (existing == null || incoming.updatedAt.compareTo(existing.updatedAt) > 0) {
          _cache[incoming.id] = incoming;
          hasChange = true;
        }
      } catch (_) {}
    }
    if (hasChange) {
      _enforceLimit();
      _notifyUi();
      _scheduleDiskWrite();
    }
  }
}
