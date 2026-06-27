import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../background_service.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import 'login_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Stats? _stats;
  List<Booking> _bookings = [];
  bool _loading = true;
  String? _error;
  String _filter = 'booked'; // booked | all
  Timer? _timer;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _refresh();
    BackgroundPoller.start();
    // App 在前台时也定时刷新列表。
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    // 监听后台服务的更新事件，待处理数量变化时立即刷新。
    _sub = BackgroundPoller.instance.on('update').listen((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final api = await ApiClient.fromStore();
      final results = await Future.wait([
        api.bookings(status: _filter == 'all' ? null : 'booked'),
        api.stats(),
      ]);
      if (!mounted) return;
      setState(() {
        _bookings = results[0] as List<Booking>;
        _stats = results[1] as Stats;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _logout();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '无法连接服务器';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    await Store.setToken(null);
    BackgroundPoller.pollNow();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeThroughRoute(const LoginPage()));
  }

  Future<void> _verify(Booking b) async {
    await _act(() async => (await ApiClient.fromStore()).verify(b.id), '已通过');
  }

  Future<void> _cancel(Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消预约'),
        content: Text('确认取消「${b.applicantName}」的预约？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认取消')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async => (await ApiClient.fromStore()).cancel(b.id), '已取消');
  }

  Future<void> _act(Future<void> Function() fn, String okMsg) async {
    try {
      await fn();
      BackgroundPoller.pollNow(); // 让后台立即撤掉对应通知
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _stats?.booked ?? 0;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                  color: AppColors.brand50, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: const Text('🎙️', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('录音实验室 · 后台',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate800)),
                Text('预约管理控制台',
                    style: TextStyle(fontSize: 11, color: AppColors.slate400)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '提醒设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).push(fadeThroughRoute(const SettingsPage())),
          ),
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null) _errorBanner(_error!),
                  if (pendingCount > 0)
                    FadeSlideIn(child: _pendingBanner(pendingCount)),
                  FadeSlideIn(
                      delay: const Duration(milliseconds: 80),
                      child: _statsGrid()),
                  const SizedBox(height: 18),
                  FadeSlideIn(
                      delay: const Duration(milliseconds: 140),
                      child: _filterTabs()),
                  const SizedBox(height: 12),
                  ...List.generate(
                    _bookings.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 180 + i * 55),
                      child: _bookingCard(_bookings[i]),
                    ),
                  ),
                  if (_bookings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text('暂无预约记录',
                            style: TextStyle(color: AppColors.slate400)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _errorBanner(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.rose50, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppColors.rose, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(msg, style: const TextStyle(color: AppColors.rose))),
        ]),
      );

  Widget _pendingBanner(int count) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.rose, Color(0xFFE11D48)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x33F43F5E), blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            const Pulse(
                child: Icon(Icons.notifications_active,
                    color: Colors.white, size: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count 条预约待处理',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const Text('处理（通过 / 取消）后提醒才会消失',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                BackgroundPoller.silence();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已静音本轮提醒（未处理仍会再次提醒）')));
              },
              style: TextButton.styleFrom(
                  backgroundColor: Colors.white24, foregroundColor: Colors.white),
              child: const Text('静音'),
            ),
          ],
        ),
      );

  Widget _statsGrid() {
    final s = _stats;
    final items = [
      ('总预约', s?.total ?? 0, [AppColors.brand500, AppColors.brand600]),
      ('待处理', s?.booked ?? 0, [const Color(0xFFFBBF24), AppColors.amber]),
      ('已通过', s?.verified ?? 0, [const Color(0xFF34D399), AppColors.emerald]),
      ('今日', s?.today ?? 0, [AppColors.brand500, AppColors.brand600]),
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.92,
      children: items
          .map((it) => Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: it.$3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedCount(it.$2,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(it.$1,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _filterTabs() {
    Widget tab(String key, String label) {
      final active = _filter == key;
      return GestureDetector(
        onTap: () {
          setState(() {
            _filter = key;
            _loading = true;
          });
          _refresh();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: active ? AppColors.brand500 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: active ? AppColors.brand500 : AppColors.slate200),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.slate600)),
        ),
      );
    }

    return Row(children: [
      tab('booked', '待处理'),
      const SizedBox(width: 10),
      tab('all', '全部记录'),
    ]);
  }

  Widget _bookingCard(Booking b) {
    final label = statusLabels[b.status] ?? b.status;
    final (Color bg, Color fg) = switch (b.status) {
      'booked' => (AppColors.amber50, AppColors.amber700),
      'verified' => (AppColors.emerald50, AppColors.emerald700),
      _ => (AppColors.slate100, AppColors.slate500),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.applicantName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.slate800)),
                      const SizedBox(height: 2),
                      Text(b.phone,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.slate400)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(20)),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(Icons.meeting_room_outlined, b.resource.name),
            _infoRow(Icons.event_outlined, '${b.date}  ${b.slot.name} ${b.slot.range}'),
            _infoRow(Icons.groups_outlined,
                '${b.numPeople} 人 / ${b.quantity} 套${b.instructor.isNotEmpty ? '  ·  指导：${b.instructor}' : ''}'),
            if (b.description.isNotEmpty)
              _infoRow(Icons.notes_outlined, b.description),
            if (b.status == 'booked') ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _verify(b),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emerald),
                    label: const Text('通过'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _cancel(b),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.rose,
                      side: const BorderSide(color: AppColors.rose),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    label: const Text('取消'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.slate400),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.slate600))),
          ],
        ),
      );
}
