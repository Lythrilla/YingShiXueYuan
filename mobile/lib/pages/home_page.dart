import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../background_service.dart';
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

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    BackgroundPoller.start();
    // 后台 isolate 收到 SSE / 轮询事件后会 invoke 这些消息到 UI。
    _subs.add(BackgroundPoller.instance.on('update').listen((_) {
      if (mounted) bumpRefresh();
    }));
    _subs.add(BackgroundPoller.instance.on('sse').listen((event) {
      final connected = (event?['connected'] ?? false) as bool;
      appConnected.value = connected;
    }));
    _subs.add(BackgroundPoller.instance.on('door').listen((event) {
      if (event != null) _showDoorBanner(event);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
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
      _scaffold('数据概览', const OverviewTab(), showStatus: true),
      _scaffold('预约管理', const BookingsTab()),
      const ResourcesPage(),
      _scaffold('更多', const MorePage()),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
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

  Widget _scaffold(String title, Widget body, {bool showStatus = false}) {
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
          if (showStatus) _connectionChip(),
          IconButton(
            tooltip: '提醒设置',
            icon: const Icon(Icons.settings_outlined, color: AppColors.ink700),
            onPressed: () => Navigator.of(context)
                .push(fadeThroughRoute(const SettingsPage())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }

  Widget _connectionChip() {
    return ValueListenableBuilder<bool>(
      valueListenable: appConnected,
      builder: (context, connected, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Container(
                height: 8,
                width: 8,
                decoration: BoxDecoration(
                    color: connected
                        ? AppColors.emerald500
                        : AppColors.ink300,
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(connected ? '实时' : '连接中',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.ink400)),
            ],
          ),
        );
      },
    );
  }
}
