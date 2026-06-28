import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../background_service.dart';
import '../native.dart';
import '../permissions.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import 'bookings_tab.dart';
import 'more_page.dart';
import 'overview_tab.dart';
import 'resources_page.dart';
import 'settings_page.dart';

/// 应用主壳：底部导航（概览 / 预约 / 资源 / 更多）+ SSE 驱动的实时刷新。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _index = 0;
  bool _permGranted = true;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resumeBackgroundPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePermissions());
    // 后台 isolate 收到 SSE / 轮询事件后会 invoke 这些消息到 UI。
    _subs.add(BackgroundPoller.instance.on('update').listen((_) {
      if (mounted) bumpRefresh();
    }));
    _subs.add(BackgroundPoller.instance.on('door').listen((event) {
      if (event != null) _showDoorBanner(event);
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeBackgroundPolling();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      BackgroundPoller.start();
    }
  }

  Future<void> _resumeBackgroundPolling() async {
    await Native.syncNativeAlertPoller();
    await BackgroundPoller.start();
    BackgroundPoller.reconnect();
    BackgroundPoller.pollNow();
    bumpRefresh();
  }

  Future<void> _ensurePermissions() async {
    final granted = await AppPermissions.requestNotification();
    if (granted) {
      await AppPermissions.requestBatteryExemption();
      // 权限到位后立即重连推送并刷新一次，确保马上能收到通知。
      await _resumeBackgroundPolling();
    }
    if (mounted) setState(() => _permGranted = granted);
  }

  void _showDoorBanner(Map<String, dynamic> data) {
    if (!mounted) return;
    final resource = (data['resource'] ?? '') as String;
    final slot = (data['slot'] ?? '') as String;
    final duty = (data['duty'] ?? '') as String;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.accent600,
      duration: const Duration(seconds: 6),
      content: Text(
          '该去开门了：$resource · $slot · 负责人 ${duty.isEmpty ? '全体管理员' : duty}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _scaffold('数据概览', const OverviewTab()),
      _scaffold('预约管理', const BookingsTab()),
      const ResourcesPage(),
      _scaffold('更多', const MorePage()),
    ];
    return Scaffold(
      body: AnimatedIndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.ink100,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: '概览'),
          NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: '预约'),
          NavigationDestination(
              icon: Icon(Icons.meeting_room_outlined),
              selectedIcon: Icon(Icons.meeting_room),
              label: '资源'),
          NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: '更多'),
        ],
      ),
    );
  }

  Widget _scaffold(String title, Widget body) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const BrandMark(size: 30),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink900)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '提醒设置',
            icon: const Icon(Icons.settings_outlined, color: AppColors.ink700),
            onPressed: () => Navigator.of(context)
                .push(fadeThroughRoute(const SettingsPage())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _permGranted
          ? body
          : Column(children: [_permissionBanner(), Expanded(child: body)]),
    );
  }

  Widget _permissionBanner() {
    return Material(
      color: AppColors.rose50,
      child: InkWell(
        onTap: () async {
          await AppPermissions.openSettings();
          await _ensurePermissions();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            const Icon(Icons.notifications_off_outlined,
                color: AppColors.rose600, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('通知权限未开启，将收不到任何预约提醒。点此前往系统设置开启。',
                  style: TextStyle(fontSize: 12.5, color: AppColors.rose600)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.rose600, size: 18),
          ]),
        ),
      ),
    );
  }
}
