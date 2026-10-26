import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/favorite_item_model.dart';

class FavoritesService {
  static final FavoritesService _instance = FavoritesService._();
  static FavoritesService get instance => _instance;
  FavoritesService._();

  final Map<String, FavoriteItem> _cache = {};
  Timer? _writeDebounce;
  bool _isInitialized = false;

  /// ValueNotifier để UI (Tab Yêu thích, nút tim, menu action) tự động cập nhật
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// Danh sách ID đã xóa, cần đồng bộ lên server
  final Set<String> _pendingDeletions = {};
  List<String> get pendingDeletions => _pendingDeletions.toList();
  void clearPendingDeletions() => _pendingDeletions.clear();

  /// Khởi tạo và nạp danh sách yêu thích từ file JSON vào RAM
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_favorites.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map && data['items'] is List) {
            for (final raw in data['items']) {
              if (raw is Map<String, dynamic>) {
                final item = FavoriteItem.fromJson(raw);
                if (item.id.isNotEmpty) {
                  _cache[item.id] = item;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('FavoritesService.init error: $e');
    } finally {
      _isInitialized = true;
      _notify();
    }
  }

  /// Kiểm tra xem phim đã có trong danh sách yêu thích chưa (O(1))
  bool isFavorite(String id) => _cache.containsKey(id);

  /// Lấy danh sách phim yêu thích
  List<FavoriteItem> getFavorites({String? category}) {
    return _cache.values
        .where((item) => category == null || item.category == category)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Bật/Tắt trạng thái yêu thích
  bool toggleFavorite(FavoriteItem item) {
    if (_cache.containsKey(item.id)) {
      _cache.remove(item.id);
      _pendingDeletions.add(item.id);
      _notify();
      _scheduleDiskWrite();
      return false; // Đã xóa khỏi yêu thích
    } else {
      _cache[item.id] = item;
      _pendingDeletions.remove(item.id);
      _notify();
      _scheduleDiskWrite();
      return true; // Đã thêm vào yêu thích
    }
  }

  void addFavorite(FavoriteItem item) {
    _cache[item.id] = item;
    _pendingDeletions.remove(item.id);
    _notify();
    _scheduleDiskWrite();
  }

  void removeFavorite(String id) {
    if (_cache.containsKey(id)) {
      _cache.remove(id);
      _pendingDeletions.add(id);
      _notify();
      _scheduleDiskWrite();
    }
  }

  /// Xóa mục yêu thích cục bộ khi thiết bị khác đã gỡ bỏ (không thêm vào pendingDeletions)
  void removeLocalOnly(String id) {
    if (_cache.containsKey(id)) {
      _cache.remove(id);
      _notify();
      _scheduleDiskWrite();
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
      final file = File('${dir.path}/volpi_favorites.json');
      final data = {
        'items': _cache.values.map((i) => i.toJson()).toList(),
        'savedAt': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('FavoritesService._writeToDisk error: $e');
    }
  }

  Future<void> flush() async {
    _writeDebounce?.cancel();
    await _writeToDisk();
  }

  List<Map<String, dynamic>> exportForSync({String? excludeCategory}) {
    return _cache.values
        .where((i) => excludeCategory == null || i.category != excludeCategory)
        .map((i) => i.toJson())
        .toList();
  }

  void importFromSync(List<Map<String, dynamic>> items) {
    bool hasChange = false;
    for (final raw in items) {
      try {
        final incoming = FavoriteItem.fromJson(raw);
        if (incoming.id.isEmpty) continue;
        if (!_cache.containsKey(incoming.id)) {
          _cache[incoming.id] = incoming;
          hasChange = true;
        }
      } catch (_) {}
    }
    if (hasChange) {
      _notify();
      _scheduleDiskWrite();
    }
  }
}
