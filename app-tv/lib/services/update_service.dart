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

  /// Check if a newer version is available.
  static Future<UpdateInfo?> checkForUpdate({String apiHost = _defaultApiHost}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // 1. Try VPS version endpoint first (Fastest in VN, no rate limit)
      try {
        final vpsRes = await http.get(
          Uri.parse('$apiHost/api/version?_t=${DateTime.now().millisecondsSinceEpoch}'),
        ).timeout(const Duration(seconds: 4));

        if (vpsRes.statusCode == 200) {
          final data = json.decode(utf8.decode(vpsRes.bodyBytes));
          if (data is Map<String, dynamic> && (data['version'] != null || data['tag_name'] != null)) {
            return UpdateInfo.fromJson(data, currentVersion);
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
        return UpdateInfo.fromJson(data, currentVersion);
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
    return null;
  }

  /// Downloads APK and launches Android Native Package Installer
  static Future<bool> downloadAndInstallApk({
    required String downloadUrl,
    required Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/VolPi-Media-Update.apk';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        debugPrint('Download APK HTTP status error: ${response.statusCode}');
        client.close();
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      try {
        await for (final chunk in response.stream) {
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
        client.close();
      }

      // Launch native Android installer
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('Download/Install APK error: $e');
      return false;
    }
  }

  /// Triggers 1-click in-place update for TrollStore on iOS
  static Future<bool> installIpaTrollStore(String ipaUrl) async {
    try {
      // 1. Try trollstore:// URL scheme (Official TrollStore 2.0+ scheme)
      final trollstoreUri = Uri.parse('trollstore://install?url=${Uri.encodeComponent(ipaUrl)}');
      if (await canLaunchUrl(trollstoreUri)) {
        return await launchUrl(trollstoreUri, mode: LaunchMode.externalApplication);
      }

      // 2. Fallback: Open direct download link in Safari
      final directUri = Uri.parse(ipaUrl);
      return await launchUrl(directUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Install IPA error: $e');
      return false;
    }
  }
}
