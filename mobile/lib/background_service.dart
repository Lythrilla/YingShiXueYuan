import 'dart:async';

import 'package:flutter/foundation.dart';

import 'alert_engine.dart';
import 'api_client.dart';
import 'models.dart';
import 'sse_client.dart';
import 'store.dart';

/// 前台轮询器：仅在 App 存活（前台）时工作，维持一条 SSE 长连接 + 低频兜底轮询，
/// 有新预约 / 开门提醒时震动一下。
///
/// 不再使用前台服务 / 保活：状态栏没有任何常驻通知，也不会再因 dataSync 前台服务
/// 超时而崩溃。App 被划掉 / 退到后台后本轮询自然停止，后台提醒交由服务端厂商推送负责。
class BackgroundPoller {
  BackgroundPoller._();

  static final BackgroundPoller _instance = BackgroundPoller._();
  static BackgroundPoller get instance => _instance;

  final Map<String, StreamController<Map<String, dynamic>?>> _events = {};
  Timer? _timer;
  SseClient? _sse;
  bool _started = false;

  /// 订阅事件流（update / door）。
  Stream<Map<String, dynamic>?> on(String event) => _events
      .putIfAbsent(
        event,
        () => StreamController<Map<String, dynamic>?>.broadcast(),
      )
      .stream;

  void _emit(String event, Map<String, dynamic> data) =>
      _events[event]?.add(data);

  /// 兼容旧入口：现在无需任何初始化。
  static Future<void> configure() async {}

  static Future<void> start() => _instance._start();
  static void pollNow() => _instance._poll();
  static void settingsChanged() => _instance._reschedule();
  static void silence() => AlertEngine.stop();
  static void reconnect() => _instance._connectSse();

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await _reschedule();
    await _connectSse();
    await _poll();
  }

  Future<void> _connectSse() async {
    _sse?.stop();
    final token = await Store.token();
    if (token == null || token.isEmpty) return;
    final api = await ApiClient.fromStore();
    _sse = SseClient(uri: api.sseUri(), onEvent: _onSseEvent)..start();
  }

  Future<void> _reschedule() async {
    _timer?.cancel();
    final secs = await Store.pollSeconds();
    _timer = Timer.periodic(Duration(seconds: secs), (_) => _poll());
  }

  /// 处理 SSE 推送：审批类事件触发即时刷新；开门提醒触发震动。
  void _onSseEvent(Map<String, dynamic> data) {
    final type = (data['type'] ?? '') as String;
    if (type == 'door_reminder') {
      _handleDoorReminder(data);
      return;
    }
    // new_booking / update / verify / cancel 等：即时拉取一次最新待处理。
    _poll();
  }

  /// 开门提醒：到点震动一下并通知 UI 弹横幅。
  Future<void> _handleDoorReminder(Map<String, dynamic> data) async {
    try {
      final reminder = DoorReminder.fromJson(data);
      // 同一条预约只提醒一次。
      final fresh = await Store.markDoorReminded(reminder.bookingId);
      if (!fresh) return;
      await AlertEngine.fire();
      _emit('door', data);
    } catch (e) {
      debugPrint('door reminder error: $e');
    }
  }

  /// 单次轮询：拉取待处理预约 → 有新预约则震动 → 通知 UI 刷新。
  Future<void> _poll() async {
    final token = await Store.token();
    if (token == null || token.isEmpty) {
      await Store.setActivePendingNotificationIds({});
      await Store.setSeenPendingIds({});
      await AlertEngine.stop();
      _emit('update', {'loggedIn': false});
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
      } else if (newIds.isNotEmpty) {
        // 有新的待处理预约：震动一下。
        await AlertEngine.fire();
      }

      _emit('update', {
        'loggedIn': true,
        'pending': pendingIds.length,
        'newCount': newIds.length,
      });
    } catch (e) {
      debugPrint('poll error: $e');
      _emit('update', {'error': e.toString()});
    }
  }
}
