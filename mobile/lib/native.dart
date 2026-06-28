import 'package:flutter/services.dart';

import 'store.dart';

/// 与原生（Android）交互：系统铃声选择、跳转系统通知设置。
/// 仅在 UI isolate（已附着 Activity）可用。
class Native {
  static const _channel = MethodChannel('yingshi/native');

  /// 弹出系统铃声选择器，返回 {uri,title}；用户取消返回 null。
  static Future<({String uri, String title})?> pickRingtone(
      String? current) async {
    final res = await _channel.invokeMapMethod<String, dynamic>(
        'pickRingtone', {'current': current});
    if (res == null || res['cancelled'] == true) return null;
    final uri = (res['uri'] ?? '') as String;
    final title = (res['title'] ?? '系统铃声') as String;
    return (uri: uri, title: title);
  }

  /// 跳转到本应用某个通知渠道的系统设置页（可在系统里自定义铃声/重要性）。
  static Future<void> openChannelSettings(String channelId) =>
      _channel.invokeMethod('openChannelSettings', {'channelId': channelId});

  /// 跳转到本应用的系统通知设置页。
  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod('openNotificationSettings');

  /// 启动 Android 原生预约监听兜底：直接连服务器 SSE/轮询并发原生通知。
  static Future<void> startNativeAlertPoller({
    String? token,
    bool? sound,
    bool? vibration,
    bool? fullscreen,
    bool? relentless,
    int? pollSeconds,
  }) =>
      _channel.invokeMethod('startNativeAlertPoller', {
        'token': token,
        'sound': sound,
        'vibration': vibration,
        'fullscreen': fullscreen,
        'relentless': relentless,
        'pollSeconds': pollSeconds,
      });

  /// 把 Flutter 存储里的 token 与提醒设置同步到独立 :alert 原生进程。
  static Future<void> syncNativeAlertPoller({String? token}) async =>
      startNativeAlertPoller(
        token: token ?? await Store.token(),
        sound: await Store.alertSound(),
        vibration: await Store.alertVibration(),
        fullscreen: await Store.alertFullscreen(),
        relentless: await Store.alertRelentless(),
        pollSeconds: await Store.pollSeconds(),
      );

  /// 设备厂商（如 Xiaomi / HUAWEI / OPPO / vivo / samsung）。
  static Future<String> manufacturer() async =>
      (await _channel.invokeMethod<String>('manufacturer')) ?? '';

  /// 是否已被加入「电池优化白名单」（忽略电池优化）。
  static Future<bool> isIgnoringBatteryOptimizations() async =>
      (await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ??
      false;

  /// 直接弹出系统「忽略电池优化」请求框。
  static Future<void> requestIgnoreBatteryOptimizations() =>
      _channel.invokeMethod('requestIgnoreBatteryOptimizations');

  /// 跳转到厂商「自启动 / 后台运行」白名单设置页；找不到时退回应用详情页。
  /// 返回是否成功跳到了厂商专用页面。
  static Future<bool> openAutoStartSettings() async =>
      (await _channel.invokeMethod<bool>('openAutoStartSettings')) ?? false;

  /// 是否已被允许使用「全屏通知」（Android 14+ 锁屏来电式弹窗的前提）。
  static Future<bool> canUseFullScreenIntent() async =>
      (await _channel.invokeMethod<bool>('canUseFullScreenIntent')) ?? true;

  /// 跳转到系统「全屏通知」权限设置页（Android 14+）。
  static Future<void> requestFullScreenIntent() =>
      _channel.invokeMethod('requestFullScreenIntent');
}
