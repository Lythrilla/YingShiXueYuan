import 'package:shared_preferences/shared_preferences.dart';

/// 统一的本地存储（服务器地址、登录令牌、提醒偏好）。
/// 同时被 UI isolate 与后台服务 isolate 读取，因此读前都先 `reload()`。
class Store {
  static const _kToken = 'token';
  static const _kUsername = 'username';
  static const _kRole = 'role';

  static const _kAlertSound = 'alert_sound';
  static const _kAlertVibration = 'alert_vibration';
  static const _kAlertFullscreen = 'alert_fullscreen';
  static const _kAlertRelentless = 'alert_relentless';
  static const _kPollSeconds = 'poll_seconds';
  static const _kRingtoneUri = 'ringtone_uri';
  static const _kRingtoneTitle = 'ringtone_title';
  static const _kSeenPendingIds = 'seen_pending_ids';
  static const _kActivePendingNotificationIds =
      'active_pending_notification_ids';

  /// 服务器地址写死，用户无需也无法修改。
  static const defaultServerUrl = 'http://117.72.222.31:8888';

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  // ---------- 连接 ----------
  // 地址写死，始终使用固定服务器。
  static Future<String> serverUrl() async => defaultServerUrl;

  static Future<String?> token() async => (await _prefs()).getString(_kToken);

  static Future<void> setToken(String? v) async {
    final p = await _prefs();
    if (v == null) {
      await p.remove(_kToken);
    } else {
      await p.setString(_kToken, v);
    }
  }

  static Future<String?> username() async =>
      (await _prefs()).getString(_kUsername);

  static Future<void> setUsername(String v) async =>
      (await _prefs()).setString(_kUsername, v);

  static Future<String> role() async =>
      (await _prefs()).getString(_kRole) ?? 'staff';

  static Future<void> setRole(String v) async =>
      (await _prefs()).setString(_kRole, v);

  static Future<bool> isSuper() async => (await role()) == 'super';

  // ---------- 提醒偏好 ----------
  static Future<bool> alertSound() async =>
      (await _prefs()).getBool(_kAlertSound) ?? true;
  static Future<void> setAlertSound(bool v) async =>
      (await _prefs()).setBool(_kAlertSound, v);

  static Future<bool> alertVibration() async =>
      (await _prefs()).getBool(_kAlertVibration) ?? true;
  static Future<void> setAlertVibration(bool v) async =>
      (await _prefs()).setBool(_kAlertVibration, v);

  static Future<bool> alertFullscreen() async =>
      (await _prefs()).getBool(_kAlertFullscreen) ?? true;
  static Future<void> setAlertFullscreen(bool v) async =>
      (await _prefs()).setBool(_kAlertFullscreen, v);

  /// 是否「不处理就一直响」——每个轮询周期只要有待处理就重复提醒。
  /// 默认开启：后台管理端必须强提醒，直到预约被处理才停止。
  static Future<bool> alertRelentless() async =>
      (await _prefs()).getBool(_kAlertRelentless) ?? true;
  static Future<void> setAlertRelentless(bool v) async =>
      (await _prefs()).setBool(_kAlertRelentless, v);

  static Future<int> pollSeconds() async =>
      (await _prefs()).getInt(_kPollSeconds) ?? 10;
  static Future<void> setPollSeconds(int v) async =>
      (await _prefs()).setInt(_kPollSeconds, v.clamp(10, 600));

  /// 自定义提醒铃声（系统铃声 content:// URI）；为空时用内置 alarm.mp3。
  static Future<String?> ringtoneUri() async =>
      (await _prefs()).getString(_kRingtoneUri);
  static Future<String> ringtoneTitle() async =>
      (await _prefs()).getString(_kRingtoneTitle) ?? '内置默认铃声';
  static Future<void> setRingtone(String? uri, String title) async {
    final p = await _prefs();
    if (uri == null || uri.isEmpty) {
      await p.remove(_kRingtoneUri);
    } else {
      await p.setString(_kRingtoneUri, uri);
    }
    await p.setString(_kRingtoneTitle, title);
  }

  // ---------- 跨 isolate 共享：已提醒过的待处理 ID ----------
  static Set<int> _intSet(List<String> list) {
    return list.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<Set<int>> seenPendingIds() async {
    final list = (await _prefs()).getStringList(_kSeenPendingIds) ?? const [];
    return _intSet(list);
  }

  static Future<void> setSeenPendingIds(Set<int> ids) async {
    await (await _prefs()).setStringList(
      _kSeenPendingIds,
      ids.map((e) => e.toString()).toList(),
    );
  }

  static Future<void> removeSeenPendingId(int id) async {
    final ids = await seenPendingIds();
    ids.remove(id);
    await setSeenPendingIds(ids);
  }

  static Future<Set<int>> activePendingNotificationIds() async {
    final list =
        (await _prefs()).getStringList(_kActivePendingNotificationIds) ??
        const [];
    return _intSet(list);
  }

  static Future<void> setActivePendingNotificationIds(Set<int> ids) async {
    await (await _prefs()).setStringList(
      _kActivePendingNotificationIds,
      ids.map((e) => e.toString()).toList(),
    );
  }

  static Future<void> addActivePendingNotificationId(int id) async {
    final ids = await activePendingNotificationIds();
    ids.add(id);
    await setActivePendingNotificationIds(ids);
  }

  static Future<void> removeActivePendingNotificationId(int id) async {
    final ids = await activePendingNotificationIds();
    ids.remove(id);
    await setActivePendingNotificationIds(ids);
  }

  // ---------- 开门提醒去重：已提醒过的预约 ID ----------
  static const _kRemindedDoorIds = 'reminded_door_ids';

  static Future<Set<int>> remindedDoorIds() async {
    final list = (await _prefs()).getStringList(_kRemindedDoorIds) ?? const [];
    return list.map(int.parse).toSet();
  }

  static Future<bool> markDoorReminded(int bookingId) async {
    final p = await _prefs();
    final set = (p.getStringList(_kRemindedDoorIds) ?? const [])
        .map(int.parse)
        .toSet();
    if (set.contains(bookingId)) return false;
    set.add(bookingId);
    // 仅保留最近 200 条，避免无限增长。
    final trimmed = set.toList()..sort();
    final keep = trimmed.length > 200
        ? trimmed.sublist(trimmed.length - 200)
        : trimmed;
    await p.setStringList(
      _kRemindedDoorIds,
      keep.map((e) => e.toString()).toList(),
    );
    return true;
  }
}
