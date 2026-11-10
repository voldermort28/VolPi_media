import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/gdrive_model.dart';

class GDriveCacheManager {
  static final GDriveCacheManager _instance = GDriveCacheManager._internal();
  factory GDriveCacheManager() => _instance;
  GDriveCacheManager._internal();

  // In-memory cache for instant 0ms access during app session
  final Map<String, GDriveFolderContentResult> _memoryCache = {};

  /// Synchronously retrieve cached folder content from memory (0ms)
  GDriveFolderContentResult? get(String folderId) {
    return _memoryCache[folderId];
  }

  /// Store in memory immediately and persist to disk asynchronously
  Future<void> set(String folderId, GDriveFolderContentResult result) async {
    _memoryCache[folderId] = result;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/gdrive_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final file = File('${cacheDir.path}/$folderId.json');
      await file.writeAsString(json.encode(result.toJson()));
    } catch (_) {}
  }

  /// Load from disk cache on app startup if memory is empty
  Future<GDriveFolderContentResult?> loadFromDisk(String folderId) async {
    if (_memoryCache.containsKey(folderId)) {
      return _memoryCache[folderId];
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/gdrive_cache/$folderId.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonMap = json.decode(content);
        if (jsonMap is Map<String, dynamic>) {
          final result = GDriveFolderContentResult.fromJson(jsonMap);
          _memoryCache[folderId] = result;
          return result;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Clear cache
  void clear([String? folderId]) {
    if (folderId != null) {
      _memoryCache.remove(folderId);
    } else {
      _memoryCache.clear();
    }
  }
}
