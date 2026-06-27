import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'alert_engine.dart';
import 'api_client.dart';
import 'notification_service.dart';
import 'store.dart';

/// 后台前台服务：常驻轮询「待处理预约」，并驱动强提醒。
class BackgroundPoller {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static FlutterBackgroundService get instance => _service;

  static Future<void> configure() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        isForegroundMode: true,
        autoStart: true,
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
    if (!await _service.isRunning()) {
      await _service.startService();
    }
  }

  static void pollNow() => _service.invoke('pollNow');
  static void settingsChanged() => _service.invoke('settingsChanged');
  static void silence() => _service.invoke('silence');
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

  Future<void> reschedule() async {
    timer?.cancel();
    final secs = await Store.pollSeconds();
    timer = Timer.periodic(Duration(seconds: secs), (_) => _poll(service));
  }

  service.on('stopService').listen((_) {
    timer?.cancel();
    service.stopSelf();
  });
  service.on('pollNow').listen((_) => _poll(service));
  service.on('settingsChanged').listen((_) => reschedule());
  service.on('silence').listen((_) => AlertEngine.stop());

  await reschedule();
  await _poll(service);
}

/// 单次轮询：拉取待处理预约 → 刷新常驻通知 → 触发/停止强提醒。
@pragma('vm:entry-point')
Future<void> _poll(ServiceInstance service) async {
  final token = await Store.token();
  if (token == null || token.isEmpty) {
    await Notifications.showSummary(0);
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
    final handledOrGone = seen.difference(pendingIds);

    final relentless = await Store.alertRelentless();
    final fullscreen = await Store.alertFullscreen();

    // 每轮都重新展示（ongoing 通知不可划掉；万一被系统清掉也会重新出现）。
    for (final b in pending) {
      await Notifications.showBooking(
        b,
        fullScreen: fullscreen && newIds.contains(b.id),
        playSound: false, // 声音交给 AlertEngine 统一处理
      );
    }
    // 已处理 / 已消失的，撤掉通知。
    for (final id in handledOrGone) {
      await Notifications.cancelBooking(id);
    }
    await Notifications.showSummary(pendingIds.length);
    await Store.setSeenPendingIds(pendingIds);

    // 强提醒：有新预约时一定响；开启「不处理就一直响」时只要还有待处理就持续响。
    if (pendingIds.isNotEmpty && (newIds.isNotEmpty || relentless)) {
      await AlertEngine.fire();
    } else if (pendingIds.isEmpty) {
      await AlertEngine.stop();
    }

    if (service is AndroidServiceInstance) {
      final secs = await Store.pollSeconds();
      await service.setForegroundNotificationInfo(
        title: pendingIds.isEmpty
            ? '录音预约 · 监控中'
            : '${pendingIds.length} 条预约待处理',
        content: pendingIds.isEmpty
            ? '每 ${secs}s 检查一次，暂无待处理'
            : '处理后提醒才会消失 · 每 ${secs}s 刷新',
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
