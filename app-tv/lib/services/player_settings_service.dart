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
  bool _isInitialized = false;

  double get volume => _volume;
  bool get isMuted => _isMuted;
  double get preMuteVolume => _preMuteVolume;

  /// Khởi tạo và nạp mức âm lượng đã lưu từ file JSON vào RAM
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
          }
        }
      }
    } catch (e) {
      debugPrint('PlayerSettingsService.init error: $e');
    } finally {
      _isInitialized = true;
    }
  }

  /// Cập nhật và lưu mức âm lượng bền vững xuyên suốt các video và luồng phát
  void saveVolume({required double volume, required bool isMuted, double? preMuteVolume}) {
    _volume = volume.clamp(0.0, 1.0);
    _isMuted = isMuted;
    if (preMuteVolume != null) {
      _preMuteVolume = preMuteVolume.clamp(0.0, 1.0);
    }
    _writeToDisk();
  }

  Future<void> _writeToDisk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/volpi_player_settings.json');
      final data = {
        'volume': _volume,
        'isMuted': _isMuted,
        'preMuteVolume': _preMuteVolume,
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('PlayerSettingsService._writeToDisk error: $e');
    }
  }
}
