import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import 'store.dart';

/// 铃声 + 震动提醒引擎。
/// 用「闹钟」音频属性循环播放用户选择的系统铃声，直到 [stop] 被调用
/// （处理完待处理预约 / 点击通知动作 / 静音）。震动同样循环，与响铃同步。
class AlertEngine {
  static final AudioPlayer _player = AudioPlayer();
  static bool _contextReady = false;
  static bool _ringing = false;

  /// 用闹钟用途配置播放器：以闹钟音量播放、可穿透媒体静音 / 勿扰（取决于系统设置）。
  static Future<void> _ensureContext() async {
    if (_contextReady) return;
    await _player.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        isSpeakerphoneOn: false,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: const {AVAudioSessionOptions.duckOthers},
      ),
    ));
    _contextReady = true;
  }

  /// 触发强提醒（循环响铃 + 循环震动），遵循用户在设置里的开关。
  /// 已在响时不重复重启，避免每次轮询打断当前铃声。
  static Future<void> fire() async {
    if (_ringing) return;
    _ringing = true;
    if (await Store.alertSound()) {
      await _startRinging();
    }
    if (await Store.alertVibration()) {
      await _vibrate();
    }
  }

  static Future<void> _startRinging() async {
    try {
      await _ensureContext();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      final uri = await Store.ringtoneUri();
      if (uri != null && uri.isNotEmpty) {
        await _player.play(UrlSource(uri));
      } else {
        await _player.play(AssetSource('sounds/alarm.mp3'));
      }
    } catch (e) {
      debugPrint('ring failed: $e');
      // 用户铃声 URI 不可播放时回退到内置铃声，避免完全无声。
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.play(AssetSource('sounds/alarm.mp3'));
      } catch (e2) {
        debugPrint('ring fallback failed: $e2');
      }
    }
  }

  static Future<void> _vibrate() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (!hasVibrator) return;
      const pattern = [0, 600, 400, 600, 400, 600, 400];
      final hasAmplitude = await Vibration.hasAmplitudeControl();
      if (hasAmplitude) {
        await Vibration.vibrate(
          pattern: pattern,
          intensities: const [0, 255, 0, 255, 0, 255, 0],
          repeat: 0, // 循环震动直到 cancel
        );
      } else {
        await Vibration.vibrate(pattern: pattern, repeat: 0);
      }
    } catch (e) {
      debugPrint('vibrate failed: $e');
    }
  }

  /// 停止铃声与震动（没有待处理预约 / 用户处理后调用）。
  static Future<void> stop() async {
    _ringing = false;
    try {
      await _player.stop();
      await Vibration.cancel();
    } catch (e) {
      debugPrint('stop alert failed: $e');
    }
  }
}
