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
  static const int _maxItems = 200;
  bool _isInitialized = false;

  /// ValueNotifier để UI (như hàng Tiếp tục xem hoặc badge đồng hồ) tự động cập nhật khi có thay đổi
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// Danh sách các ID đã bị người dùng xóa, cần thông báo đồng bộ lên server
  final Set<String> _pendingDeletions = {};
  List<String> get pendingDeletions => _pendingDeletions.toList();
  void clearPendingDeletions() => _pendingDeletions.clear();

  /// Khởi tạo và nạp toàn bộ lịch sử từ file JSON vào RAM
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_watch_history.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map && data['items'] is List) {
            for (final raw in data['items']) {
              if (raw is Map<String, dynamic>) {
                final item = WatchHistoryItem.fromJson(raw);
                if (item.id.isNotEmpty) {
                  _cache[item.id] = item;
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
      _notify();
    }
  }

  /// Truy vấn O(1) tiến trình xem từ RAM — hoàn toàn đồng bộ, không bao giờ gây giật lag UI
  WatchHistoryItem? getProgress(String id) => _cache[id];

  /// Lấy tiến trình xem gần nhất của một phim/anime theo mediaId
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

  /// Lấy danh sách các phim/tập đang xem dở, sắp xếp mới xem nhất lên đầu
  List<WatchHistoryItem> getContinueWatching({String? excludeCategory, String? category}) {
    return _cache.values
        .where((item) {
          if (!item.isInProgress) return false;
          if (category != null && item.category != category) return false;
          if (excludeCategory != null && item.category == excludeCategory) return false;
          return true;
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Lấy toàn bộ lịch sử xem theo category (không giới hạn isInProgress), sắp xếp mới xem nhất lên đầu
  List<WatchHistoryItem> getHistory({String? category, String? excludeCategory}) {
    return _cache.values
        .where((item) {
          if (category != null && item.category != category) return false;
          if (excludeCategory != null && item.category == excludeCategory) return false;
          return true;
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// Lưu tiến trình xem — cập nhật RAM tức thì, gom ghi đĩa mỗi 4 giây
  void saveProgress(WatchHistoryItem item) {
    _cache[item.id] = item;
    _pendingDeletions.remove(item.id);
    _enforceLimit();
    _notify();
    _scheduleDiskWrite();
  }

  /// Xóa 1 mục khỏi lịch sử xem
  void clearProgress(String id) {
    if (_cache.containsKey(id)) {
      _cache.remove(id);
      _pendingDeletions.add(id);
      _notify();
      _scheduleDiskWrite();
    }
  }

  /// Xóa mục cục bộ khi đồng bộ nhận được lệnh xóa từ thiết bị khác (không ghi nhận vào pendingDeletions)
  void removeLocalOnly(String id) {
    if (_cache.containsKey(id)) {
      _cache.remove(id);
      _notify();
      _scheduleDiskWrite();
    }
  }

  /// Kiểm tra xem có mục lịch sử nào bắt đầu bằng tiền tố id không
  bool hasProgressForPrefix(String prefix) {
    return _cache.keys.any((k) => k == prefix || k.startsWith('$prefix:'));
  }

  /// Xóa tất cả các mục lịch sử có id bắt đầu bằng tiền tố
  void clearProgressForPrefix(String prefix) {
    final keysToRemove = _cache.keys.where((k) => k == prefix || k.startsWith('$prefix:')).toList();
    for (final k in keysToRemove) {
      _cache.remove(k);
      _pendingDeletions.add(k);
    }
    if (keysToRemove.isNotEmpty) {
      _notify();
      _scheduleDiskWrite();
    }
  }

  /// Xóa toàn bộ lịch sử
  void clearAll({String? category}) {
    if (category == null) {
      _pendingDeletions.addAll(_cache.keys);
      _cache.clear();
    } else {
      final toRemove = _cache.values.where((i) => i.category == category).map((i) => i.id).toList();
      for (final id in toRemove) {
        _cache.remove(id);
        _pendingDeletions.add(id);
      }
    }
    _notify();
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

  void _notify() {
    changeNotifier.value++;
  }

  void _scheduleDiskWrite() {
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(seconds: 4), () {
      _writeToDisk();
    });
  }

  Future<void> _writeToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_watch_history.json');
      final data = {
        'items': _cache.values.map((i) => i.toJson()).toList(),
        'savedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('WatchHistoryService._writeToDisk error: $e');
    }
  }

  /// Ghi đĩa tức thì khi app thoát hoặc đóng VideoPlayerScreen
  Future<void> flush() async {
    _writeDebounce?.cancel();
    await _writeToDisk();
  }

  /// Xuất dữ liệu cho SyncService
  List<Map<String, dynamic>> exportForSync({String? excludeCategory}) {
    return _cache.values
        .where((i) => excludeCategory == null || i.category != excludeCategory)
        .map((i) => i.toJson())
        .toList();
  }

  /// Nạp dữ liệu đồng bộ từ server, hợp nhất theo updatedAt
  void importFromSync(List<Map<String, dynamic>> items) {
    bool hasChange = false;
    for (final raw in items) {
      try {
        final incoming = WatchHistoryItem.fromJson(raw);
        if (incoming.id.isEmpty) continue;
        final existing = _cache[incoming.id];
        if (existing == null || incoming.updatedAt.compareTo(existing.updatedAt) > 0) {
          _cache[incoming.id] = incoming;
          hasChange = true;
        }
      } catch (_) {}
    }
    if (hasChange) {
      _enforceLimit();
      _notify();
      _scheduleDiskWrite();
    }
  }
}
