import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/update_model.dart';

class UpdateService {
  static const String _defaultApiHost = 'https://stremio.laboon.vn';
  static const String _fallbackGitHubApi = 'https://api.github.com/repos/voldermort28/VolPi_media/releases/latest';
  static http.Client? _activeDownloadClient;
  static bool _isDownloadCancelled = false;

  /// Hủy tiến trình tải APK đang chạy (khi người dùng bấm Bỏ qua / Hủy)
  static void cancelActiveDownload() {
    _isDownloadCancelled = true;
    try {
      _activeDownloadClient?.close();
    } catch (_) {}
    _activeDownloadClient = null;
  }

  /// Dọn dẹp file APK cài đặt còn sót lại trong cache để giải phóng bộ nhớ TV
  static Future<void> cleanupStaleApk() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/VolPi-Media-Update.apk';
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[UpdateService] Đã tự động dọn dẹp file APK update trong cache.');
      }
    } catch (e) {
      debugPrint('[UpdateService] Dọn dẹp APK error: $e');
    }
  }

  /// Check if a newer version is available.
  static Future<UpdateInfo?> checkForUpdate({String apiHost = _defaultApiHost}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 1. Try VPS version endpoint first (Fastest in VN, no rate limit)
      try {
        final vpsRes = await http.get(
          Uri.parse('$apiHost/api/version?_t=${DateTime.now().millisecondsSinceEpoch}'),
        ).timeout(const Duration(seconds: 4));

        if (vpsRes.statusCode == 200) {
          final data = json.decode(utf8.decode(vpsRes.bodyBytes));
          if (data is Map<String, dynamic> && (data['version'] != null || data['tag_name'] != null)) {
            return UpdateInfo.fromJson(data, currentVersion, currentBuild: currentBuild);
          }
        }
      } catch (e) {
        debugPrint('VPS version check fallback: $e');
      }

      // 2. Fallback to GitHub Releases API
      final ghRes = await http.get(
        Uri.parse(_fallbackGitHubApi),
        headers: {'User-Agent': 'VolPiMedia-App'},
      ).timeout(const Duration(seconds: 6));

      if (ghRes.statusCode == 200) {
        final data = json.decode(utf8.decode(ghRes.bodyBytes));
        return UpdateInfo.fromJson(data, currentVersion, currentBuild: currentBuild);
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
    return null;
  }

  static String? lastInstallError;

  /// Downloads APK and launches Android Native Package Installer
  static Future<bool> downloadAndInstallApk({
    required String downloadUrl,
    required Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    _isDownloadCancelled = false;
    lastInstallError = null;
    if (downloadUrl.trim().isEmpty) {
      lastInstallError = 'Không tìm thấy đường dẫn tải APK.';
      return false;
    }

    http.Client? client;
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/VolPi-Media-Update.apk';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      client = http.Client();
      _activeDownloadClient = client;
      final request = http.Request('GET', Uri.parse(downloadUrl.trim()));
      final response = await client.send(request).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        debugPrint('Download APK HTTP status error: ${response.statusCode}');
        lastInstallError = 'Lỗi máy chủ khi tải APK (HTTP ${response.statusCode}).';
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          if (_isDownloadCancelled) {
            break;
          }
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final progress = receivedBytes / totalBytes;
            onProgress(progress, receivedBytes, totalBytes);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (_isDownloadCancelled) {
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
        return false;
      }

      if (totalBytes > 0 && receivedBytes < totalBytes) {
        debugPrint('Download APK incomplete: $receivedBytes of $totalBytes');
        lastInstallError = 'Tải APK bị gián đoạn trước khi hoàn tất.';
        return false;
      }

      // Launch native Android installer
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type == ResultType.permissionDenied) {
        lastInstallError = 'Android chưa cấp quyền "Cài đặt ứng dụng không xác định" cho VolPi Media. Vào Cài đặt → Ứng dụng → VolPi Media để bật quyền này.';
        return false;
      }
      if (result.type != ResultType.done) {
        lastInstallError = result.message.isNotEmpty ? result.message : 'Không thể mở trình cài đặt APK.';
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Download/Install APK error: $e');
      lastInstallError = 'Kết nối bị gián đoạn khi tải APK: $e';
      return false;
    } finally {
      try {
        client?.close();
      } catch (_) {}
      if (_activeDownloadClient == client) {
        _activeDownloadClient = null;
      }
    }
  }

  /// Triggers 1-click in-place update for TrollStore on iOS (official apple-magnifier:// scheme)
  static Future<bool> installIpaTrollStore(String ipaUrl) async {
    if (ipaUrl.trim().isEmpty) return false;
    try {
      final encoded = Uri.encodeComponent(ipaUrl.trim());
      // 1. Official TrollStore 2.0+ URL scheme (apple-magnifier://install?url=...)
      final magnifierUri = Uri.parse('apple-magnifier://install?url=$encoded');
      if (await canLaunchUrl(magnifierUri)) {
        return await launchUrl(magnifierUri, mode: LaunchMode.externalApplication);
      }

      // 2. Legacy trollstore:// fallback
      final legacyUri = Uri.parse('trollstore://install?url=$encoded');
      if (await canLaunchUrl(legacyUri)) {
        return await launchUrl(legacyUri, mode: LaunchMode.externalApplication);
      }

      // 3. Fallback: Open direct download link in Safari
      final directUri = Uri.parse(ipaUrl.trim());
      return await launchUrl(directUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Install IPA error: $e');
      return false;
    }
  }
}
