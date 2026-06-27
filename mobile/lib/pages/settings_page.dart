import 'package:flutter/material.dart';

import '../alert_engine.dart';
import '../background_service.dart';
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
    _server = await Store.serverUrl();
    if (mounted) setState(() => _loaded = true);
  }

  void _notifyService() => BackgroundPoller.settingsChanged();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionTitle('提醒方式'),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    _switch('铃声提醒', '有待处理预约时循环播放铃声', _sound, (v) async {
                      await Store.setAlertSound(v);
                      setState(() => _sound = v);
                    }),
                    _divider(),
                    _switch('震动提醒', '配合铃声一起震动', _vibration, (v) async {
                      await Store.setAlertVibration(v);
                      setState(() => _vibration = v);
                    }),
                    _divider(),
                    _switch('全屏弹窗', '锁屏时也以来电式全屏弹出（仅安卓）', _fullscreen,
                        (v) async {
                      await Store.setAlertFullscreen(v);
                      setState(() => _fullscreen = v);
                    }),
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
                      _notifyService();
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
