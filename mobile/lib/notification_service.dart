import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'store.dart';

/// 新预约 / 开门提醒已改为「只震动」，不再弹任何提醒通知，也不再有前台服务常驻通知；
/// 这里仅用于清理历史遗留的通知通道与残留通知，状态栏保持干净。
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int bookingIdBase = 100000; // 历史通知 id 基数，用于清理残留
  static const int doorIdBase = 300000;

  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    final android11 = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android11 != null) {
      // 清理历史遗留的响铃 / 震动 / 汇总 / 前台服务通道（现在只震动，状态栏不再有任何通知）。
      for (final id in const [
        'yingshi_service',
        'yingshi_alert',
        'yingshi_door',
        'yingshi_alert_v2',
        'yingshi_door_v2',
        'yingshi_alert_v3',
        'yingshi_alert_sound_v3',
        'yingshi_alert_vibration_v3',
        'yingshi_alert_silent_v3',
        'yingshi_door_v3',
        'yingshi_door_sound_v3',
        'yingshi_door_vibration_v3',
        'yingshi_door_silent_v3',
        'yingshi_summary',
      ]) {
        await android11.deleteNotificationChannel(id);
      }
    }
    _inited = true;
  }

  /// 处理完 / 已不在待处理列表时，清掉可能残留的历史通知并同步本地状态。
  static Future<void> clearProcessedBooking(int bookingId) async {
    await _cancelNotification(bookingIdBase + bookingId);
    await _cancelNotification(doorIdBase + bookingId);
    await Store.removeSeenPendingId(bookingId);
  }

  static Future<void> _cancelNotification(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('notification cancel failed for $id: $e');
    }
  }
}
