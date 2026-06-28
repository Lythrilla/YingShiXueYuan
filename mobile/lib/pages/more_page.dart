import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api_client.dart';
import '../background_service.dart';
import '../native.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';
import 'admins_page.dart';
import 'keepalive_page.dart';
import 'login_page.dart';
import 'logs_page.dart';
import 'settings_page.dart';
import 'shifts_page.dart';
import 'slots_page.dart';

/// 「更多」：管理入口聚合 + 导出 + 退出登录。
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  String _username = '';
  String _role = 'staff';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final u = await Store.username();
    final r = await Store.role();
    if (mounted) {
      setState(() {
        _username = u ?? '';
        _role = r;
      });
    }
  }

  bool get _isSuper => _role == 'super';

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final api = await ApiClient.fromStore();
      final bytes = await api.exportBookings();
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/bookings_$stamp.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: '预约记录导出');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _logout() async {
    await Store.setToken(null);
    await Native.startNativeAlertPoller(token: '');
    BackgroundPoller.reconnect();
    BackgroundPoller.pollNow();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        fadeThroughRoute(const LoginPage()), (route) => false);
  }

  void _go(Widget page) =>
      Navigator.of(context).push(fadeThroughRoute(page));

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        AppCard(
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                    color: AppColors.ink900,
                    borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Text(
                    _username.isEmpty ? '?' : _username.characters.first.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_username,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink900)),
                  const SizedBox(height: 2),
                  Text(_isSuper ? '超级管理员' : '普通管理员',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.ink400)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionTitle('排期与开门'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _tile(Icons.schedule_outlined, '时间段', '管理可预约的时段',
                  () => _go(const SlotsPage())),
              _divider(),
              _tile(Icons.calendar_month_outlined, '排班 · 开门负责人',
                  '设置谁去开门、通知谁', () => _go(const ShiftsPage())),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionTitle('数据与记录'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _tile(
                _exporting ? Icons.hourglass_top : Icons.ios_share,
                '导出预约 Excel',
                '导出全部预约并分享',
                _exporting ? null : _export,
              ),
              _divider(),
              _tile(Icons.history, '操作日志', '审批 / 增删改审计',
                  () => _go(const LogsPage())),
            ],
          ),
        ),
        if (_isSuper) ...[
          const SizedBox(height: 18),
          const SectionTitle('账号'),
          AppCard(
            padding: EdgeInsets.zero,
            child: _tile(Icons.group_outlined, '管理员账号',
                '新增 / 停用 / 重置密码', () => _go(const AdminsPage())),
          ),
        ],
        const SizedBox(height: 18),
        const SectionTitle('应用'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _tile(Icons.notifications_active_outlined, '提醒设置',
                  '铃声、震动、全屏弹窗', () => _go(const SettingsPage())),
              _divider(),
              _tile(Icons.shield_outlined, '后台保活',
                  '防止划掉后台被系统杀掉', () => _go(const KeepAlivePage())),
              _divider(),
              _tile(Icons.logout, '退出登录', '', _logout,
                  danger: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider() => const Divider(height: 1, indent: 56);

  Widget _tile(IconData icon, String title, String subtitle,
      VoidCallback? onTap,
      {bool danger = false}) {
    final color = danger ? AppColors.rose600 : AppColors.ink700;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(title,
          style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: danger ? AppColors.rose600 : AppColors.ink900)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle,
              style: const TextStyle(fontSize: 12, color: AppColors.ink400)),
      trailing: onTap == null
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chevron_right, color: AppColors.ink300),
    );
  }
}
