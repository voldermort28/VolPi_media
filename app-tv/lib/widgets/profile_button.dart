import 'package:flutter/material.dart';
import 'tv_focusable_card.dart';
import 'passcode_dialog.dart';

class ProfileButton extends StatelessWidget {
  final VoidCallback onUnlocked;

  const ProfileButton({super.key, required this.onUnlocked});

  void _showPasscodeDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PasscodeDialog(onSuccess: onUnlocked),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: TvFocusableCard(
        onTap: () => _showPasscodeDialog(context),
        scale: 1.05,
        borderRadius: BorderRadius.circular(22),
        focusBorderColor: const Color(0xFF38BDF8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF334155), width: 1),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline_rounded, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Text(
                'Profile',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
