import 'package:flutter/material.dart';
import '../api/api_service.dart';
import 'netflix_layout.dart';

/// Unified root layout shell — standardized exclusively on the Netflix Design System
/// across Android TV, iPhone/iPad, Android Phone and macOS.
class AdaptiveLayout extends StatelessWidget {
  final ApiService apiService;

  const AdaptiveLayout({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return NetflixLayout(apiService: apiService);
  }
}
