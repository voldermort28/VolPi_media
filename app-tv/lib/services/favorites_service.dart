import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/favorite_item_model.dart';
import '../models/watch_history_model.dart';

class FavoritesService {
  static final FavoritesService _instance = FavoritesService._();
  static FavoritesService get instance => _instance;
  FavoritesService._();

  final Map<String, FavoriteItem> _cache = {};
  Timer? _writeDebounce;
  Future<void> _writeQueue = Future.value();
  bool _isInitialized = false;

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> syncTriggerNotifier = ValueNotifier<int>(0);

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

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_favorites.json');
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
                  final item = FavoriteItem.fromJson(raw);
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
      debugPrint('FavoritesService.init error: $e');
    } finally {
      _isInitialized = true;
      _notifyUi();
    }
  }

  bool isFavorite(String id) => _cache.containsKey(id);

  List<FavoriteItem> getFavorites({String? category, String? excludeCategory}) {
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
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  bool toggleFavorite(FavoriteItem item) {
    final isSecret = WatchHistoryItem.isSecretOrPrivateItem(item.id, item.category);
    if (_cache.containsKey(item.id)) {
      _cache.remove(item.id);
      if (!isSecret) {
        _pendingDeletions.add(item.id);
        _notifySync();
      }
      _notifyUi();
      _scheduleDiskWrite();
      return false;
    } else {
      _cache[item.id] = item;
      _pendingDeletions.remove(item.id);
      _notifyUi();
      if (!isSecret) _notifySync();
      _scheduleDiskWrite();
      return true;
    }
  }

  void addFavorite(FavoriteItem item) {
    _cache[item.id] = item;
    _pendingDeletions.remove(item.id);
    _notifyUi();
    if (!WatchHistoryItem.isSecretOrPrivateItem(item.id, item.category)) {
      _notifySync();
    }
    _scheduleDiskWrite();
  }

  void removeFavorite(String id) {
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
      final file = File('${dir.path}/volpi_favorites.json');
      final tmpFile = File('${dir.path}/volpi_favorites.json.tmp');
      final data = {
        'items': _cache.values.map((i) => i.toJson()).toList(),
        'pendingDeletions': _pendingDeletions.toList(),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await tmpFile.writeAsString(jsonEncode(data), flush: true);
      await tmpFile.rename(file.path);
    } catch (e) {
      debugPrint('FavoritesService._writeToDisk error: $e');
    }
  }

  Future<void> flush() async {
    _writeDebounce?.cancel();
    await _enqueueDiskWrite();
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

  void importFromSync(List<Map<String, dynamic>> items) {
    bool hasChange = false;
    for (final raw in items) {
      try {
        final incoming = FavoriteItem.fromJson(raw);
        if (incoming.id.isEmpty) continue;
        if (_pendingDeletions.contains(incoming.id)) continue;
        if (!_cache.containsKey(incoming.id)) {
          _cache[incoming.id] = incoming;
          hasChange = true;
        }
      } catch (_) {}
    }
    if (hasChange) {
      _notifyUi();
      _scheduleDiskWrite();
    }
  }
}
