import 'package:flutter/material.dart';

/// Safe loading overlay helper that uses an explicit [DialogRoute] and [PopScope(canPop: false)].
/// Prevents the Android TV Back key from prematurely popping the dialog and later causing
/// `Navigator.pop()` to pop the underlying screen into a black screen or deactivated-context crash.
class LoadingDialogHelper {
  static Future<T?> runWithLoading<T>(
    BuildContext context,
    Future<T> Function() task, {
    Color indicatorColor = const Color(0xFFE50914),
    String? message,
  }) async {
    if (!context.mounted) return null;
    final navigator = Navigator.of(context, rootNavigator: true);

    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: message == null
              ? CircularProgressIndicator(color: indicatorColor)
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: indicatorColor),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          decoration: TextDecoration.none,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );

    navigator.push(route);
    try {
      return await task();
    } finally {
      if (route.isActive) {
        try {
          navigator.removeRoute(route);
        } catch (_) {}
      }
    }
  }
}
