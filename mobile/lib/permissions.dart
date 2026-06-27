import 'package:permission_handler/permission_handler.dart';

/// 通知 / 后台运行所需的运行时权限。必须在前台（已附着 Activity）调用，
/// 否则 Android 13+ 不会弹出权限框，导致一条通知都收不到。
class AppPermissions {
  static Future<bool> notificationGranted() async =>
      (await Permission.notification.status).isGranted;

  /// 申请通知权限，返回是否已授予。
  static Future<bool> requestNotification() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// 申请「忽略电池优化」，避免后台监控服务被系统杀掉。
  static Future<void> requestBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return;
    await Permission.ignoreBatteryOptimizations.request();
  }

  /// 跳转系统设置页（用户曾「永久拒绝」时引导手动开启）。
  static Future<void> openSettings() => openAppSettings();
}
