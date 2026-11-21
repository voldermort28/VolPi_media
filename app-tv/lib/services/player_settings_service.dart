import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PlayerSettingsService {
  static final PlayerSettingsService _instance = PlayerSettingsService._();
  static PlayerSettingsService get instance => _instance;
  PlayerSettingsService._();

  double _volume = 1.0;
  bool _isMuted = false;
  double _preMuteVolume = 1.0;
  bool _useNetflixUI = true;
  bool _isInitialized = false;
  Timer? _writeDebounce;
  Future<void> _writeQueue = Future.value();

  final ValueNotifier<bool> uiChangeNotifier = ValueNotifier<bool>(true);

  double get volume => _volume;
  bool get isMuted => _isMuted;
  double get preMuteVolume => _preMuteVolume;
  bool get useNetflixUI => _useNetflixUI;

  /// Khởi tạo và nạp cài đặt đã lưu từ file JSON vào RAM
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_player_settings.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content);
          if (data is Map<String, dynamic>) {
            if (data['volume'] is num) {
              _volume = (data['volume'] as num).toDouble().clamp(0.0, 1.0);
            }
            if (data['isMuted'] is bool) {
              _isMuted = data['isMuted'] as bool;
            }
            if (data['preMuteVolume'] is num) {
              _preMuteVolume = (data['preMuteVolume'] as num).toDouble().clamp(0.0, 1.0);
            }
            // Mặc định thống nhất sử dụng giao diện Netflix
            _useNetflixUI = true;
            uiChangeNotifier.value = _useNetflixUI;
          }
        }
      }
    } catch (e) {
      debugPrint('PlayerSettingsService.init error: $e');
    } finally {
      _isInitialized = true;
    }
  }

  /// Cập nhật và lưu cài đặt giao diện
  void setUseNetflixUI(bool value) {
    if (_useNetflixUI != value) {
      _useNetflixUI = value;
      uiChangeNotifier.value = value;
      _scheduleWrite();
    }
  }

  /// Cập nhật và lưu mức âm lượng bền vững (có debounce 300ms chống ghi đĩa liên tục khi kéo slider)
  void saveVolume({required double volume, required bool isMuted, double? preMuteVolume}) {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = isMuted;
    if (preMuteVolume != null) {
      _preMuteVolume = preMuteVolume.clamp(0.0, 1.0);
    }
    _scheduleWrite();
  }

  void _scheduleWrite() {
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 300), () {
      _enqueueWrite();
    });
  }

  void _enqueueWrite() {
    _writeQueue = _writeQueue.then((_) => _writeToDisk()).catchError((_) {});
  }

  Future<void> _writeToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_player_settings.json');
      final tmpFile = File('${dir.path}/volpi_player_settings.json.tmp');
      final data = {
        'volume': _volume,
        'isMuted': _isMuted,
        'preMuteVolume': _preMuteVolume,
        'useNetflixUI': _useNetflixUI,
      };
      await tmpFile.writeAsString(jsonEncode(data), flush: true);
      await tmpFile.rename(file.path);
    } catch (e) {
      debugPrint('PlayerSettingsService._writeToDisk error: $e');
    }
  }
}
