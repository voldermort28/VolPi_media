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

  static String _safeKey(String folderId) {
    return folderId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  /// Synchronously retrieve cached folder content from memory (0ms)
  GDriveFolderContentResult? get(String folderId) {
    return _memoryCache[folderId];
  }

  /// Store in memory immediately and persist to temporary cache directory asynchronously
  Future<void> set(String folderId, GDriveFolderContentResult result) async {
    _memoryCache[folderId] = result;
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/gdrive_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final file = File('${cacheDir.path}/${_safeKey(folderId)}.json');
      await file.writeAsString(json.encode(result.toJson()));
    } catch (_) {}
  }

  /// Load from disk cache if memory is empty
  Future<GDriveFolderContentResult?> loadFromDisk(String folderId) async {
    if (_memoryCache.containsKey(folderId)) {
      return _memoryCache[folderId];
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gdrive_cache/${_safeKey(folderId)}.json');
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

  /// Clear both in-memory and disk cache (zero trace when exiting private area)
  Future<void> clear([String? folderId]) async {
    if (folderId != null) {
      _memoryCache.remove(folderId);
      try {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/gdrive_cache/${_safeKey(folderId)}.json');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    } else {
      _memoryCache.clear();
      try {
        final dir = await getTemporaryDirectory();
        final cacheDir = Directory('${dir.path}/gdrive_cache');
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
