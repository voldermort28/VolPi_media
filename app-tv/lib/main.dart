import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api/api_service.dart';
import 'layout/adaptive_layout.dart';

import 'services/favorites_service.dart';
import 'services/player_settings_service.dart';
import 'services/update_service.dart';
import 'services/watch_history_service.dart';
import 'services/audio_player_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Low-RAM TV & Device Optimization: limit image cache to prevent GC thrashing & lag
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 25 << 20; // 25 MB

  // Allow all orientations (TV landscape, Phone portrait/landscape, iPad both)
  try {
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
  } catch (e) {
    debugPrint('[Main] setPreferredOrientations warning: $e');
  }

  Future<void> safeInit(String name, Future<dynamic> Function() task) async {
    try {
      await task().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('[Main] $name init fallback: $e');
    }
  }

  // Khởi tạo các service lưu trữ nhẹ vào RAM (có timeout bảo vệ tuyệt đối không treo màn hình khởi động)
  await Future.wait([
    safeInit('WatchHistory', () => WatchHistoryService.instance.init()),
    safeInit('Favorites', () => FavoritesService.instance.init()),
    safeInit('PlayerSettings', () => PlayerSettingsService.instance.init()),
  ]);

  final apiService = ApiService();

  runApp(VolPiMediaApp(apiService: apiService));

  // Khởi tạo AudioService và dọn dẹp APK ngầm sau khi UI đã hiển thị (không bao giờ chặn runApp)
  unawaited(VolPiAudioHandler.init());
  unawaited(UpdateService.cleanupStaleApk());
}

class VolPiMediaApp extends StatelessWidget {
  final ApiService apiService;

  const VolPiMediaApp({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VolPi Media',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF38BDF8),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF0284C7),
          surface: Color(0xFF1E293B),
        ),
        fontFamily: 'Roboto',
      ),
      home: AdaptiveLayout(apiService: apiService),
    );
  }
}
