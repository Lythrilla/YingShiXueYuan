import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';
import 'store.dart';

/// 通知通道。前台保活服务合用一条静音常驻通知（MIN，状态栏不显示图标）；
/// 开门提醒弹一条可见通知 + 震动；新预约可见通知由原生 :alert 进程负责。
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // 换新通道 id：通知通道的 importance 创建后不可更改，旧机器上 'yingshi_service'
  // 已是 LOW，降不到 MIN；用新 id 让 MIN（状态栏不显示图标）真正生效。
  static const serviceChannelId = 'yingshi_service_v2';

  // 开门提醒可见通知通道（新 id，与旧版区分）。
  static const doorChannelId = 'yingshi_door_v4';

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
      // 清理历史遗留的响铃 / 震动 / 汇总通道，以及旧的前台服务 / 守护通道
      // （现在三个前台服务合用一条 MIN 通知，状态栏不再显示图标）。
      for (final id in const [
        'yingshi_service',
        'yingshi_keepalive_guard',
        'yingshi_alert_process_guard',
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
      // 前台服务共用的常驻通知通道：MIN（状态栏不显示图标、静音、折叠在通知栏最底部）。
      await android11.createNotificationChannel(
        const AndroidNotificationChannel(
          serviceChannelId,
          '后台运行',
          description: '保持后台运行以接收新预约提醒',
          importance: Importance.min,
          playSound: false,
          enableVibration: false,
        ),
      );
      // 开门提醒的可见通知通道：HIGH 以便弹横幅 / 状态栏可见；不出声（震动单独触发）。
      await android11.createNotificationChannel(
        const AndroidNotificationChannel(
          doorChannelId,
          '开门提醒',
          description: '预约开始前提醒负责人去开门',
          importance: Importance.high,
          playSound: false,
          enableVibration: false,
        ),
      );
    }
    _inited = true;
  }

  /// 开门提醒：弹一条可见通知（震动由 AlertEngine 单独触发）。
  static Future<void> showDoorReminder(DoorReminder r) async {
    const android = AndroidNotificationDetails(
      doorChannelId,
      '开门提醒',
      channelDescription: '预约开始前提醒负责人去开门',
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: false,
      autoCancel: true,
    );
    try {
      await _plugin.show(
        doorIdBase + r.bookingId,
        r.title,
        r.body,
        const NotificationDetails(
          android: android,
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('show door reminder failed: $e');
    }
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
