import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'models.dart';
import 'store.dart';

/// 通知通道与展示逻辑。被 UI / 后台两个 isolate 共用，因此设计为静态方法。
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const summaryChannelId = 'yingshi_summary';
  static const alertChannelId = 'yingshi_alert';
  static const serviceChannelId = 'yingshi_service';

  static const int summaryNotificationId = 9990;
  static const int bookingIdBase = 100000; // 每条待处理 = base + bookingId

  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse: _onTapBackground,
    );

    final android11 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android11 != null) {
      await android11.requestNotificationsPermission();
      // 高优先级、带自定义铃声、可触发全屏的提醒通道。
      await android11.createNotificationChannel(const AndroidNotificationChannel(
        alertChannelId,
        '新预约强提醒',
        description: '有新的待处理预约时的强提醒（声音 / 震动 / 全屏）',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('alarm'),
        enableVibration: true,
        enableLights: true,
      ));
      await android11
          .createNotificationChannel(const AndroidNotificationChannel(
        summaryChannelId,
        '待处理汇总',
        description: '常驻显示当前待处理预约数量',
        importance: Importance.high,
      ));
      // 后台前台服务的常驻通知通道（须在服务 startForeground 前创建）。
      await android11
          .createNotificationChannel(const AndroidNotificationChannel(
        serviceChannelId,
        '后台监控服务',
        description: '常驻后台监控，定时检查新的待处理预约',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ));
    }
    _inited = true;
  }

  /// 展示 / 刷新单条待处理预约通知（ongoing = 不可滑动划掉）。
  static Future<void> showBooking(Booking b,
      {required bool fullScreen, required bool playSound}) async {
    final actions = <AndroidNotificationAction>[
      AndroidNotificationAction('approve', '通过', showsUserInterface: false),
      AndroidNotificationAction('cancel', '取消', showsUserInterface: false),
    ];
    final android = AndroidNotificationDetails(
      alertChannelId,
      '新预约强提醒',
      channelDescription: '有新的待处理预约时的强提醒',
      importance: Importance.max,
      priority: Priority.max,
      ongoing: true, // 不可被滑动清除
      autoCancel: false,
      playSound: playSound,
      sound: playSound
          ? const RawResourceAndroidNotificationSound('alarm')
          : null,
      fullScreenIntent: fullScreen,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      actions: actions,
      styleInformation: BigTextStyleInformation(
        '${b.resource.name} · ${b.date} ${b.slot.name} ${b.slot.range}\n'
        '电话 ${b.phone}${b.instructor.isNotEmpty ? ' · 指导 ${b.instructor}' : ''} · ${b.numPeople}人/${b.quantity}套',
        contentTitle: '待处理预约：${b.applicantName}',
      ),
    );
    const ios = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentSound: true,
    );
    await _plugin.show(
      bookingIdBase + b.id,
      '待处理预约：${b.applicantName}',
      '${b.resource.name} · ${b.date} ${b.slot.name}',
      NotificationDetails(android: android, iOS: ios),
      payload: 'booking:${b.id}',
    );
  }

  static Future<void> cancelBooking(int bookingId) =>
      _plugin.cancel(bookingIdBase + bookingId);

  /// 汇总通知：常驻显示「X 条待处理」。count=0 时清除。
  static Future<void> showSummary(int count) async {
    if (count <= 0) {
      await _plugin.cancel(summaryNotificationId);
      return;
    }
    final android = AndroidNotificationDetails(
      summaryChannelId,
      '待处理汇总',
      channelDescription: '常驻显示当前待处理预约数量',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
    );
    const ios = DarwinNotificationDetails(presentSound: false);
    await _plugin.show(
      summaryNotificationId,
      '$count 条预约待处理',
      '点击进入 App 审批，处理后提醒才会消失',
      NotificationDetails(android: android, iOS: ios),
      payload: 'summary',
    );
  }

  static void _onTap(NotificationResponse r) => _handleResponse(r);

  @pragma('vm:entry-point')
  static void _onTapBackground(NotificationResponse r) => _handleResponse(r);

  /// 处理通知上的「通过 / 取消」动作按钮，直接调用后端接口。
  static Future<void> _handleResponse(NotificationResponse r) async {
    final payload = r.payload ?? '';
    if (!payload.startsWith('booking:')) return;
    final id = int.tryParse(payload.substring('booking:'.length));
    if (id == null) return;
    final action = r.actionId;
    if (action != 'approve' && action != 'cancel') return;
    try {
      final api = await ApiClient.fromStore();
      if (action == 'approve') {
        await api.verify(id);
      } else {
        await api.cancel(id);
      }
      await cancelBooking(id);
      final seen = await Store.seenPendingIds()..remove(id);
      await Store.setSeenPendingIds(seen);
    } catch (e) {
      debugPrint('notification action failed: $e');
    }
  }
}

/// 状态标签便于通知文案复用。
String statusLabel(String s) => statusLabels[s] ?? s;
