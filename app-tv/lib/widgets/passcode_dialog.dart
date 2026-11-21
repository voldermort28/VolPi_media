import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'tv_focusable_card.dart';

class PasscodeDialog extends StatefulWidget {
  final VoidCallback onSuccess;
  final bool isChangePinMode;

  const PasscodeDialog({
    super.key,
    required this.onSuccess,
    this.isChangePinMode = false,
  });

  static const String _defaultSalt = 'volpi_pin_salt_v2';
  static const String _defaultPinHash = 'b37200e433fa48ba53135345680c2bf513c89f54f1f7bafb891e47c45632afb5';
  static const int _maxFailedAttempts = 5;
  static const int _cooldownSeconds = 30;

  static int _failedAttempts = 0;
  static DateTime? _lockedUntil;
  static String _cachedSalt = _defaultSalt;
  static String _cachedHash = _defaultPinHash;
  static bool _configLoaded = false;

  static String _hashPin(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static Future<void> _loadPinConfig() async {
    if (_configLoaded) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_pin_config.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map) {
          if (data['salt'] is String && data['hash'] is String && (data['hash'] as String).isNotEmpty) {
            _cachedSalt = data['salt'] as String;
            _cachedHash = data['hash'] as String;
          }
          if (data['failedAttempts'] is int) {
            _failedAttempts = data['failedAttempts'] as int;
          }
          if (data['lockedUntilMs'] is int) {
            final dt = DateTime.fromMillisecondsSinceEpoch(data['lockedUntilMs'] as int);
            if (dt.isAfter(DateTime.now())) {
              _lockedUntil = dt;
            }
          }
        }
      }
    } catch (_) {}
    _configLoaded = true;
  }

  static Future<void> _savePinConfig() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_pin_config.json');
      final payload = {
        'salt': _cachedSalt,
        'hash': _cachedHash,
        'failedAttempts': _failedAttempts,
        'lockedUntilMs': _lockedUntil?.millisecondsSinceEpoch,
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {}
  }

  static Future<void> updatePin(String newPin) async {
    await _loadPinConfig();
    final newSalt = 'volpi_pin_${DateTime.now().microsecondsSinceEpoch}';
    _cachedSalt = newSalt;
    _cachedHash = _hashPin(newPin, newSalt);
    _failedAttempts = 0;
    _lockedUntil = null;
    await _savePinConfig();
  }

  /// Hiển thị dialog đổi mã PIN 4 số từ bên trong Kho Riêng Tư
  static Future<void> showChangePinDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => PasscodeDialog(
        isChangePinMode: true,
        onSuccess: () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã cập nhật mã PIN riêng tư mới thành công!'),
                backgroundColor: Color(0xFF10B981),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  State<PasscodeDialog> createState() => _PasscodeDialogState();
}

class _PasscodeDialogState extends State<PasscodeDialog> {
  String _code = '';
  String? _pendingNewPin; // Used during 2-step Change PIN confirmation
  String? _errorMessage;
  bool _isShakeError = false;
  int _remainingLockSeconds = 0;
  Timer? _lockCountdownTimer;

  @override
  void initState() {
    super.initState();
    _initLockState();
  }

  @override
  void dispose() {
    _lockCountdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLockState() async {
    await PasscodeDialog._loadPinConfig();
    if (!mounted) return;
    _syncCooldownTimer();
  }

  void _syncCooldownTimer() {
    _lockCountdownTimer?.cancel();
    final lockedUntil = PasscodeDialog._lockedUntil;
    if (lockedUntil == null || !lockedUntil.isAfter(DateTime.now())) {
      if (_remainingLockSeconds != 0 && mounted) {
        setState(() {
          _remainingLockSeconds = 0;
          _errorMessage = null;
        });
      }
      return;
    }

    void tick() {
      if (!mounted) return;
      final diff = lockedUntil.difference(DateTime.now()).inSeconds;
      if (diff <= 0) {
        _lockCountdownTimer?.cancel();
        PasscodeDialog._lockedUntil = null;
        PasscodeDialog._failedAttempts = 0;
        PasscodeDialog._savePinConfig();
        setState(() {
          _remainingLockSeconds = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _remainingLockSeconds = diff;
          _errorMessage = 'Nhập sai quá 5 lần. Tạm khóa ${diff}s';
        });
      }
    }

    tick();
    _lockCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  bool get _isLocked => _remainingLockSeconds > 0 && !widget.isChangePinMode;

  void _onNumberPressed(String number) {
    if (_isLocked) return;
    if (_code.length < 4) {
      setState(() {
        _code += number;
        _errorMessage = null;
        _isShakeError = false;
      });

      if (_code.length == 4) {
        // Hiển thị chấm thứ 4 trong 120ms để người dùng thấy phản hồi rõ ràng
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted && _code.length == 4) _verifyCode();
        });
      }
    }
  }

  void _onBackspace() {
    if (_isLocked) return;
    if (_code.isNotEmpty) {
      setState(() {
        _code = _code.substring(0, _code.length - 1);
        _errorMessage = null;
        _isShakeError = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (widget.isChangePinMode) {
      if (_pendingNewPin == null) {
        setState(() {
          _pendingNewPin = _code;
          _code = '';
          _errorMessage = null;
        });
        return;
      }
      if (_code == _pendingNewPin) {
        await PasscodeDialog.updatePin(_code);
        if (!mounted) return;
        Navigator.of(context).pop();
        widget.onSuccess();
      } else {
        setState(() {
          _pendingNewPin = null;
          _code = '';
          _isShakeError = true;
          _errorMessage = 'Mã PIN xác nhận không khớp. Vui lòng nhập lại!';
        });
      }
      return;
    }

    await PasscodeDialog._loadPinConfig();
    final computed = PasscodeDialog._hashPin(_code, PasscodeDialog._cachedSalt);
    if (computed == PasscodeDialog._cachedHash) {
      PasscodeDialog._failedAttempts = 0;
      PasscodeDialog._lockedUntil = null;
      PasscodeDialog._savePinConfig();
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    } else {
      PasscodeDialog._failedAttempts += 1;
      if (PasscodeDialog._failedAttempts >= PasscodeDialog._maxFailedAttempts) {
        PasscodeDialog._lockedUntil = DateTime.now().add(
          const Duration(seconds: PasscodeDialog._cooldownSeconds),
        );
        PasscodeDialog._savePinConfig();
        if (!mounted) return;
        setState(() {
          _code = '';
          _isShakeError = true;
        });
        _syncCooldownTimer();
      } else {
        final left = PasscodeDialog._maxFailedAttempts - PasscodeDialog._failedAttempts;
        PasscodeDialog._savePinConfig();
        if (!mounted) return;
        setState(() {
          _isShakeError = true;
          _errorMessage = 'Mã truy cập không đúng (còn $left lần thử)';
          _code = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String titleText = widget.isChangePinMode
        ? (_pendingNewPin == null ? 'Đặt Mã PIN Mới' : 'Xác Nhận Mã PIN Mới')
        : 'Xác thực Hồ Sơ';
    final String subtitleText = widget.isChangePinMode
        ? (_pendingNewPin == null ? 'Nhập mã PIN 4 chữ số mới' : 'Nhập lại 4 chữ số vừa đặt để xác nhận')
        : 'Nhập mã định danh cá nhân để tiếp tục';

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
            _onNumberPressed('0');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
            _onNumberPressed('1');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
            _onNumberPressed('2');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
            _onNumberPressed('3');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
            _onNumberPressed('4');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
            _onNumberPressed('5');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
            _onNumberPressed('6');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
            _onNumberPressed('7');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
            _onNumberPressed('8');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
            _onNumberPressed('9');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.backspace || key == LogicalKeyboardKey.delete) {
            _onBackspace();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: _isShakeError || _isLocked ? const Color(0xFFF43F5E) : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLocked
                      ? Icons.lock_clock_rounded
                      : (widget.isChangePinMode ? Icons.pin_rounded : Icons.account_circle),
                  size: 46,
                  color: _isLocked ? const Color(0xFFF43F5E) : const Color(0xFF38BDF8),
                ),
                const SizedBox(height: 10),
                Text(
                  titleText,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),

                // 4 PIN Dots/Boxes
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final bool filled = index < _code.length;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 44,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isShakeError || _isLocked
                              ? const Color(0xFFF43F5E)
                              : (filled ? const Color(0xFF38BDF8) : const Color(0xFF475569)),
                          width: filled || _isShakeError ? 2 : 1,
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
                    style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 12.5, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 20),

                // TV D-pad Onscreen Keypad
                Opacity(
                  opacity: _isLocked ? 0.4 : 1.0,
                  child: Column(
                    children: [
                      _buildKeypadRow(['1', '2', '3'], autoFocusFirst: true),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> numbers, {bool autoFocusFirst = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: numbers.asMap().entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: _buildNumberKey(entry.value, autoFocus: autoFocusFirst && entry.key == 0),
        );
      }).toList(),
    );
  }

  Widget _buildNumberKey(String number, {bool autoFocus = false}) {
    return SizedBox(
      width: 68,
      height: 46,
      child: TvFocusableCard(
        autoFocus: autoFocus,
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
      height: 46,
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
