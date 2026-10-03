import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api/api_service.dart';
import 'layout/adaptive_layout.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Low-RAM TV & Device Optimization: limit image cache to prevent GC thrashing & lag
  PaintingBinding.instance.imageCache.maximumSize = 120;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 25 << 20; // 25 MB

  // Allow all orientations (TV landscape, Phone portrait/landscape, iPad both)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final apiService = ApiService();

  runApp(VolPiMediaApp(apiService: apiService));
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
