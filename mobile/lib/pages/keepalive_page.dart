import 'package:flutter/material.dart';

import '../native.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// 后台保活引导页：
/// 应用本身已用前台服务 + 守护服务 + 一像素保活 + 心跳/Job 兜底保活；
/// 但小米/华为/OPPO/vivo/三星等
/// 深度定制系统在「上划清理后台」后会杀进程并阻止自启动，必须由用户在系统里
/// 授予「自启动 / 后台运行」白名单并关闭电池优化，代码无法绕过这一系统策略。
class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage> {
  String _manufacturer = '';
  bool _batteryOk = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final m = await Native.manufacturer();
    final b = await Native.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _manufacturer = m;
      _batteryOk = b;
      _loading = false;
    });
  }

  Future<void> _requestBattery() async {
    await Native.requestIgnoreBatteryOptimizations();
    await _refresh();
  }

  Future<void> _openAutoStart() async {
    final ok = await Native.openAutoStartSettings();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到厂商自启动页，已打开应用详情页，请手动开启「自启动 / 后台运行」')),
      );
    }
  }

  String get _hint {
    final m = _manufacturer.toLowerCase();
    if (m.contains('xiaomi') || m.contains('redmi')) {
      return '小米 / Redmi：安全中心 → 应用管理 → 自启动，打开本应用；并在「省电策略」里设为「无限制」。';
    }
    if (m.contains('huawei') || m.contains('honor')) {
      return '华为 / 荣耀：手机管家 → 应用启动管理，关闭本应用的「自动管理」，手动允许自启动、关联启动、后台活动。';
    }
    if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
      return 'OPPO / realme / 一加：设置 → 电池 → 应用耗电管理，允许本应用后台运行 / 自启动。';
    }
    if (m.contains('vivo') || m.contains('iqoo')) {
      return 'vivo / iQOO：i 管家 → 应用管理 → 自启动 / 后台高耗电，允许本应用。';
    }
    if (m.contains('samsung')) {
      return '三星：设置 → 电池 → 后台使用限制，将本应用设为「从不休眠的应用」。';
    }
    return '请在系统「电池 / 应用管理」里允许本应用自启动、后台运行，并取消休眠限制。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('后台保活')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '让监控不被系统杀掉',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink900,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '应用已开启前台常驻服务、守护服务、一像素息屏保活、心跳和 Job 兜底，'
                        '并会在被杀后自动拉起。但部分手机（小米/华为/OPPO/vivo/三星等）'
                        '在「上划清理后台」后会强制杀掉进程并禁止自启动——这属于系统策略，必须按下面两步手动授权。',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.ink600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionTitle('第 1 步 · 电池优化'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _batteryOk
                                ? Icons.check_circle
                                : Icons.error_outline,
                            size: 20,
                            color: _batteryOk
                                ? AppColors.emerald600
                                : AppColors.rose600,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _batteryOk ? '已允许（无电池优化）' : '尚未允许，建议开启',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _batteryOk
                                  ? AppColors.emerald600
                                  : AppColors.rose600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _batteryOk ? null : _requestBattery,
                          child: Text(_batteryOk ? '已设置' : '允许忽略电池优化'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const SectionTitle('第 2 步 · 自启动 / 后台运行'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hint,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.ink600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _openAutoStart,
                          child: const Text('打开自启动设置'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
