import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// 提醒引擎：有新预约 / 开门提醒时震动一下。
/// 不再响铃、不再循环——只做一次短震，保持安静、低打扰。
class AlertEngine {
  /// 触发提醒：震动一下（单次短震）。
  static Future<void> fire() async {
    try {
      if (!(await Vibration.hasVibrator())) return;
      await Vibration.vibrate(duration: 500);
    } catch (e) {
      debugPrint('vibrate failed: $e');
    }
  }

  /// 停止震动（处理完 / 静音时调用）。
  static Future<void> stop() async {
    try {
      await Vibration.cancel();
    } catch (e) {
      debugPrint('stop vibrate failed: $e');
    }
  }
}
