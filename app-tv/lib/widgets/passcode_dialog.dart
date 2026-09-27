import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tv_focusable_card.dart';

class PasscodeDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const PasscodeDialog({super.key, required this.onSuccess});

  @override
  State<PasscodeDialog> createState() => _PasscodeDialogState();
}

class _PasscodeDialogState extends State<PasscodeDialog> {
  String _code = '';
  final String _correctPasscode = '3105';
  String? _errorMessage;

  void _onNumberPressed(String number) {
    if (_code.length < 4) {
      setState(() {
        _code += number;
        _errorMessage = null;
      });

      if (_code.length == 4) {
        _verifyCode();
      }
    }
  }

  void _onBackspace() {
    if (_code.isNotEmpty) {
      setState(() {
        _code = _code.substring(0, _code.length - 1);
        _errorMessage = null;
      });
    }
  }

  void _verifyCode() {
    if (_code == _correctPasscode) {
      Navigator.of(context).pop();
      widget.onSuccess();
    } else {
      setState(() {
        _errorMessage = 'Mã truy cập không hợp lệ';
        _code = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) _onNumberPressed('0');
          if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) _onNumberPressed('1');
          if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) _onNumberPressed('2');
          if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) _onNumberPressed('3');
          if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) _onNumberPressed('4');
          if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) _onNumberPressed('5');
          if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) _onNumberPressed('6');
          if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) _onNumberPressed('7');
          if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) _onNumberPressed('8');
          if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) _onNumberPressed('9');
          if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) _onBackspace();
          if (key == LogicalKeyboardKey.escape) Navigator.of(context).pop();
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: const Color(0xFF0F172A), // Dark slate
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFF334155), width: 1.5),
        ),
        child: Container(
          width: 380,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle, size: 48, color: Color(0xFF38BDF8)),
              const SizedBox(height: 12),
              const Text(
                'Xác thực Hồ Sơ',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nhập mã định danh cá nhân để tiếp tục',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 20),

              // 4 PIN Dots/Boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final bool filled = index < _code.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 44,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: filled ? const Color(0xFF38BDF8) : const Color(0xFF475569),
                        width: filled ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      filled ? '●' : '',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  );
                }),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],

              const SizedBox(height: 24),

              // TV D-pad Onscreen Keypad
              Column(
                children: [
                  _buildKeypadRow(['1', '2', '3']),
                  const SizedBox(height: 10),
                  _buildKeypadRow(['4', '5', '6']),
                  const SizedBox(height: 10),
                  _buildKeypadRow(['7', '8', '9']),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionKey(
                        icon: Icons.close,
                        onTap: () => Navigator.of(context).pop(),
                        color: Colors.redAccent.withOpacity(0.2),
                      ),
                      const SizedBox(width: 12),
                      _buildNumberKey('0'),
                      const SizedBox(width: 12),
                      _buildActionKey(
                        icon: Icons.backspace_outlined,
                        onTap: _onBackspace,
                        color: Colors.amber.withOpacity(0.2),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: numbers.map((n) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _buildNumberKey(n),
        );
      }).toList(),
    );
  }

  Widget _buildNumberKey(String number) {
    return SizedBox(
      width: 68,
      height: 48,
      child: TvFocusableCard(
        onTap: () => _onNumberPressed(number),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: const Color(0xFF1E293B),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildActionKey({required IconData icon, required VoidCallback onTap, required Color color}) {
    return SizedBox(
      width: 68,
      height: 48,
      child: TvFocusableCard(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: color,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
