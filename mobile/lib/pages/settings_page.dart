import 'package:flutter/material.dart';

import '../alert_engine.dart';
import '../store.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _server = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _server = await Store.serverUrl();
    if (mounted) setState(() => _loaded = true);
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
                _sectionTitle('提醒方式'),
                const AppCard(
                  child: Row(children: [
                    Icon(Icons.vibration, size: 18, color: AppColors.ink400),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '有新预约 / 开门提醒时震动一下，不响铃、不弹通知。',
                        style:
                            TextStyle(fontSize: 13, color: AppColors.ink600),
                      ),
                    ),
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
                  onPressed: () => AlertEngine.fire(),
                  icon: const Icon(Icons.vibration),
                  label: const Text('测试震动'),
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
}
