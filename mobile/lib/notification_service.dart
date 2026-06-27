import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'alert_engine.dart';
import 'api_client.dart';
import 'models.dart';
import 'store.dart';

/// 通知通道与展示逻辑。被 UI / 后台两个 isolate 共用，因此设计为静态方法。
class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const summaryChannelId = 'yingshi_summary';
  // _v2：声音 / 震动改由 AlertEngine 统一处理（用用户选的铃声、可循环），
  // 通道本身静音；通道一旦创建声音不可变，故升级时换新 id 并删除旧通道。
  static const alertChannelId = 'yingshi_alert_v2';
  static const serviceChannelId = 'yingshi_service';
  static const doorChannelId = 'yingshi_door_v2';

  static const int summaryNotificationId = 9990;
  static const int bookingIdBase = 100000; // 每条待处理 = base + bookingId
  static const int doorIdBase = 300000; // 每条开门提醒 = base + bookingId

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
      // 删除旧的带固定铃声通道，改用静音通道（声音/震动交给 AlertEngine）。
      await android11.deleteNotificationChannel('yingshi_alert');
      await android11.deleteNotificationChannel('yingshi_door');
      // 高优先级、可触发全屏的提醒通道；通道静音，铃声/震动由 AlertEngine 处理，
      // 这样才能用用户在设置里选择的系统铃声并循环。
      await android11.createNotificationChannel(const AndroidNotificationChannel(
        alertChannelId,
        '新预约强提醒',
        description: '有新的待处理预约时的强提醒（全屏）',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
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
      // 开门提醒通道：到点提醒负责人去开门，强提醒（声音 / 震动 / 全屏）。
      await android11
          .createNotificationChannel(const AndroidNotificationChannel(
        doorChannelId,
        '开门提醒',
        description: '预约时段临近时提醒负责人去开门',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
        enableLights: true,
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
      playSound: false, // 声音由 AlertEngine 统一播放（用户铃声 + 循环）
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

  /// 展示「开门提醒」强提醒（区别于审批提醒：标题、通道、payload 都不同）。
  static Future<void> showDoorReminder(DoorReminder r,
      {required bool fullScreen, required bool playSound}) async {
    final android = AndroidNotificationDetails(
      doorChannelId,
      '开门提醒',
      channelDescription: '预约时段临近时提醒负责人去开门',
      importance: Importance.max,
      priority: Priority.max,
      ongoing: false,
      autoCancel: true,
      playSound: false, // 声音由 AlertEngine 统一播放（用户铃声 + 循环）
      fullScreenIntent: fullScreen,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      color: const Color(0xFFDB6238),
      styleInformation: BigTextStyleInformation(
        '${r.date} ${r.slot}（${r.startTime} 开始）\n'
        '申请人 ${r.applicant} · 负责人 ${r.dutyLabel}',
        contentTitle: r.title,
      ),
    );
    const ios = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentSound: true,
    );
    await _plugin.show(
      doorIdBase + r.bookingId,
      r.title,
      r.body,
      NotificationDetails(android: android, iOS: ios),
      payload: 'door:${r.bookingId}',
    );
  }

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
    // 一旦从通知上处理，立即停掉正在响的提醒。
    await AlertEngine.stop();
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
