import 'package:flutter/material.dart';

import '../alert_engine.dart';
import '../background_service.dart';
import '../native.dart';
import '../permissions.dart';
import '../store.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _sound = true;
  bool _vibration = true;
  bool _fullscreen = true;
  bool _relentless = true;
  bool _notifGranted = true;
  bool _fsiGranted = true;
  String _ringtone = '';
  String _server = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _sound = await Store.alertSound();
    _vibration = await Store.alertVibration();
    _fullscreen = await Store.alertFullscreen();
    _relentless = await Store.alertRelentless();
    _notifGranted = await AppPermissions.notificationGranted();
    _fsiGranted = await Native.canUseFullScreenIntent();
    _ringtone = await Store.ringtoneTitle();
    _server = await Store.serverUrl();
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _pickRingtone() async {
    final current = await Store.ringtoneUri();
    final picked = await Native.pickRingtone(current);
    if (picked == null) return;
    await Store.setRingtone(picked.uri, picked.title);
    if (mounted) setState(() => _ringtone = picked.title);
  }

  Future<void> _notifyService() async {
    BackgroundPoller.settingsChanged();
    await Native.syncNativeAlertPoller();
  }

  Future<void> _ensureFullScreenPermission() async {
    if (await Native.canUseFullScreenIntent()) {
      if (mounted) setState(() => _fsiGranted = true);
      return;
    }
    await Native.requestFullScreenIntent();
    final granted = await Native.canUseFullScreenIntent();
    if (mounted) setState(() => _fsiGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_notifGranted) ...[
                  _sectionTitle('通知权限'),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      onTap: () async {
                        await AppPermissions.openSettings();
                        await _load();
                      },
                      leading: const Icon(Icons.notifications_off_outlined,
                          color: AppColors.rose600),
                      title: const Text('通知权限未开启',
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.rose600)),
                      subtitle: const Text('未开启将收不到任何预约提醒，点此前往系统设置开启',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.ink400)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.rose600),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                _sectionTitle('提醒方式'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _switch('铃声提醒', '有待处理预约时循环播放铃声', _sound, (v) async {
                      await Store.setAlertSound(v);
                      setState(() => _sound = v);
                      await _notifyService();
                    }),
                    _divider(),
                    ListTile(
                      onTap: _pickRingtone,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: const Icon(Icons.music_note_outlined,
                          color: AppColors.ink500),
                      title: const Text('提醒铃声',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink800)),
                      subtitle: Text('当前：$_ringtone · 点击从系统铃声中选择',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.ink400)),
                      trailing: const Icon(Icons.chevron_right,
                          color: AppColors.ink300),
                    ),
                    _divider(),
                    _switch('震动提醒', '配合铃声一起震动', _vibration, (v) async {
                      await Store.setAlertVibration(v);
                      setState(() => _vibration = v);
                      await _notifyService();
                    }),
                    _divider(),
                    _switch('全屏弹窗', '锁屏时也以来电式全屏弹出（仅安卓）', _fullscreen,
                        (v) async {
                      await Store.setAlertFullscreen(v);
                      setState(() => _fullscreen = v);
                      if (v) await _ensureFullScreenPermission();
                      await _notifyService();
                    }),
                    if (_fullscreen && !_fsiGranted) ...[
                      _divider(),
                      ListTile(
                        onTap: _ensureFullScreenPermission,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: const Icon(Icons.warning_amber_rounded,
                            color: AppColors.rose600),
                        title: const Text('全屏通知权限未开启',
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.rose600)),
                        subtitle: const Text(
                            'Android 14+ 需手动允许，否则锁屏来电式弹窗不会出现。点此前往开启',
                            style:
                                TextStyle(fontSize: 12, color: AppColors.ink400)),
                        trailing: const Icon(Icons.chevron_right,
                            color: AppColors.rose600),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 18),
                _sectionTitle('提醒强度'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _switch('不处理就一直提醒', '只要还有待处理预约，就会持续响铃 / 震动',
                        _relentless, (v) async {
                      await Store.setAlertRelentless(v);
                      setState(() => _relentless = v);
                      await _notifyService();
                    }),
                  ]),
                ),
                const SizedBox(height: 18),
                _sectionTitle('服务器'),
                AppCard(
                  child: Row(children: [
                    const Icon(Icons.dns_outlined,
                        size: 18, color: AppColors.ink400),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(_server,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.ink600))),
                  ]),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    await AlertEngine.fire();
                    await Future.delayed(const Duration(seconds: 3));
                    await AlertEngine.stop();
                  },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('测试提醒（响铃 3 秒）'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: AppColors.ink400)),
      );

  Widget _switch(
          String title, String subtitle, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.ink900,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(title,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink800)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
      );

  Widget _divider() => const Divider(height: 1, color: AppColors.ink100);
}
