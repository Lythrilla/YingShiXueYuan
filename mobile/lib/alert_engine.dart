import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import 'store.dart';

/// 铃声 + 震动提醒引擎。可循环播放直到被显式停止（处理完毕）。
class AlertEngine {
  static final AudioPlayer _player = AudioPlayer();
  static bool _ringing = false;

  /// 触发一次强提醒（铃声循环 + 震动），遵循用户在设置里的开关。
  static Future<void> fire() async {
    if (await Store.alertSound()) {
      await _startRinging();
    }
    if (await Store.alertVibration()) {
      await _vibrate();
    }
  }

  static Future<void> _startRinging() async {
    try {
      if (_ringing) return;
      _ringing = true;
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/alarm.mp3'));
    } catch (e) {
      debugPrint('ring failed: $e');
      _ringing = false;
    }
  }

  static Future<void> _vibrate() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (!hasVibrator) return;
      await Vibration.vibrate(
        pattern: const [0, 600, 300, 600, 300, 600],
        intensities: const [0, 255, 0, 255, 0, 255],
      );
    } catch (e) {
      debugPrint('vibrate failed: $e');
    }
  }

  /// 停止铃声（当没有待处理预约时调用）。
  static Future<void> stop() async {
    try {
      _ringing = false;
      await _player.stop();
      await Vibration.cancel();
    } catch (e) {
      debugPrint('stop alert failed: $e');
    }
  }
}
