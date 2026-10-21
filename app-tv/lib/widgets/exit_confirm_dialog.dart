import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_focusable_card.dart';

class ExitConfirmDialog extends StatelessWidget {
  const ExitConfirmDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const ExitConfirmDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
      ),
      title: const Row(
        children: [
          Icon(Icons.exit_to_app_rounded, color: Color(0xFF38BDF8), size: 28),
          SizedBox(width: 10),
          Text(
            'Thoát ứng dụng?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: const Text(
        'Bạn có chắc chắn muốn thoát khỏi VolPi Media không?',
        style: TextStyle(
          color: Color(0xFFCBD5E1),
          fontSize: 14,
          height: 1.4,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TvFocusableCard(
              autoFocus: true, // Focus mặc định vào nút "Ở lại" để tránh bấm nhầm Back 2 lần
              onTap: () => Navigator.of(context).pop(false),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'Ở lại',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            TvFocusableCard(
              onTap: () {
                Navigator.of(context).pop(true);
                SystemNavigator.pop();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE50914).withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Thoát',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
