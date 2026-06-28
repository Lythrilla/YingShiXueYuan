import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'alert_engine.dart';
import 'api_client.dart';
import 'models.dart';
import 'notification_service.dart';
import 'sse_client.dart';
import 'store.dart';

/// 后台前台服务：维持 Flutter 侧刷新；Android 预约强提醒由原生 :alert 进程负责。
class BackgroundPoller {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static FlutterBackgroundService get instance => _service;

  static Future<void> configure() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: true,
        autoStartOnBoot: true,
        notificationChannelId: Notifications.serviceChannelId,
        initialNotificationTitle: '录音预约 · 监控中',
        initialNotificationContent: '正在监控新的待处理预约',
        foregroundServiceNotificationId: 8888,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        onForeground: onStart,
        onBackground: _onIosBackground,
        autoStart: true,
      ),
    );
  }

  static Future<void> start() async {
    try {
      if (!await _service.isRunning()) {
        await _service.startService();
      }
    } catch (e) {
      debugPrint('background service start failed: $e');
    }
  }

  static void pollNow() => _service.invoke('pollNow');
  static void settingsChanged() => _service.invoke('settingsChanged');
  static void silence() => _service.invoke('silence');
  static void reconnect() => _service.invoke('reconnect');
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Notifications.init();
  await _poll(service);
  return true;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Notifications.init();

  Timer? timer;
  SseClient? sse;

  // SSE 长连接：服务器有新事件时即时推送，几乎不耗电。
  // 同时保留一个低频兜底轮询，应对连接尚未建立 / 偶发丢包。
  Future<void> connectSse() async {
    sse?.stop();
    final token = await Store.token();
    if (token == null || token.isEmpty) return;
    final api = await ApiClient.fromStore();
    sse = SseClient(
      uri: api.sseUri(),
      onEvent: (data) => _onSseEvent(service, data),
    )..start();
  }

  Future<void> reschedule() async {
    timer?.cancel();
    final secs = await Store.pollSeconds();
    timer = Timer.periodic(Duration(seconds: secs), (_) => _poll(service));
  }

  service.on('stopService').listen((_) {
    timer?.cancel();
    sse?.stop();
    service.stopSelf();
  });
  service.on('pollNow').listen((_) => _poll(service));
  service.on('settingsChanged').listen((_) => reschedule());
  service.on('silence').listen((_) => AlertEngine.stop());
  service.on('reconnect').listen((_) => connectSse());

  await reschedule();
  await connectSse();
  await _poll(service);
}

/// 处理 SSE 推送：审批类事件触发即时刷新；开门提醒触发强提醒。
@pragma('vm:entry-point')
Future<void> _onSseEvent(
  ServiceInstance service,
  Map<String, dynamic> data,
) async {
  final type = (data['type'] ?? '') as String;
  if (type == 'door_reminder') {
    await _handleDoorReminder(service, data);
    return;
  }
  // new_booking / update / verify / cancel 等：即时拉取一次最新待处理。
  await _poll(service);
}

/// 开门提醒：到点推送强提醒给负责人（区别于审批提醒）。
@pragma('vm:entry-point')
Future<void> _handleDoorReminder(
  ServiceInstance service,
  Map<String, dynamic> data,
) async {
  try {
    final reminder = DoorReminder.fromJson(data);
    // 同一条预约只提醒一次。
    final fresh = await Store.markDoorReminded(reminder.bookingId);
    if (!fresh) return;
    final fullscreen = await Store.alertFullscreen();
    final sound = await Store.alertSound();
    final vibration = await Store.alertVibration();
    await Notifications.showDoorReminder(
      reminder,
      fullScreen: fullscreen,
      playSound: sound,
      vibrate: vibration,
    );
    await AlertEngine.fire();
    service.invoke('door', data);
  } catch (e) {
    debugPrint('door reminder error: $e');
  }
}

/// 单次轮询：拉取待处理预约 → 刷新 Flutter 前台服务状态与 UI。
@pragma('vm:entry-point')
Future<void> _poll(ServiceInstance service) async {
  final token = await Store.token();
  if (token == null || token.isEmpty) {
    await Store.setActivePendingNotificationIds({});
    await Store.setSeenPendingIds({});
    await AlertEngine.stop();
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: '录音预约 · 未登录',
        content: '请在 App 内登录后台账号以开启监控',
      );
    }
    service.invoke('update', {'loggedIn': false});
    return;
  }

  try {
    final api = await ApiClient.fromStore();
    final pending = await api.pendingBookings();
    final pendingIds = pending.map((b) => b.id).toSet();
    final seen = await Store.seenPendingIds();
    final newIds = pendingIds.difference(seen);
    await Store.setActivePendingNotificationIds(pendingIds);
    await Store.setSeenPendingIds(pendingIds);

    if (pendingIds.isEmpty) {
      await AlertEngine.stop();
    }

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: pendingIds.isEmpty
            ? '录音预约 · 监控中'
            : '${pendingIds.length} 条预约待处理',
        content: pendingIds.isEmpty ? '实时监控中，暂无待处理预约' : '处理后提醒才会消失',
      );
    }

    service.invoke('update', {
      'loggedIn': true,
      'pending': pendingIds.length,
      'newCount': newIds.length,
    });
  } catch (e) {
    debugPrint('poll error: $e');
    service.invoke('update', {'error': e.toString()});
  }
}
