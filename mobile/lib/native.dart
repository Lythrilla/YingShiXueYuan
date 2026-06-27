import 'package:flutter/services.dart';

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
}
