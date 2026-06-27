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
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('再想想')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.rose600),
              child: const Text('确认取消')),
        ],
      ),
    );
    if (ok != true) return;
    await _act(() async => (await ApiClient.fromStore()).cancel(b.id), '已取消');
  }

  Future<void> _act(Future<void> Function() fn, String okMsg) async {
    try {
      await fn();
      BackgroundPoller.pollNow();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(okMsg)));
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
            const BrandMark(size: 32),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('录音系预约后台',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.ink900)),
                Text('河北科技大学影视学院',
                    style: TextStyle(fontSize: 11, color: AppColors.ink400)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '提醒设置',
            icon: const Icon(Icons.settings_outlined, color: AppColors.ink700),
            onPressed: () => Navigator.of(context)
                .push(fadeThroughRoute(const SettingsPage())),
          ),
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout, color: AppColors.ink700),
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.ink900,
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.ink900))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null) _errorBanner(_error!),
                  if (pendingCount > 0)
                    FadeSlideIn(child: _pendingBanner(pendingCount)),
                  FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: _statsGrid()),
                  const SizedBox(height: 18),
                  FadeSlideIn(
                      delay: const Duration(milliseconds: 120),
                      child: _filterTabs()),
                  const SizedBox(height: 12),
                  ...List.generate(
                    _bookings.length,
                    (i) => FadeSlideIn(
                      delay: Duration(milliseconds: 160 + i * 50),
                      child: _bookingCard(_bookings[i]),
                    ),
                  ),
                  if (_bookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 56),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 40, color: AppColors.ink300),
                            const SizedBox(height: 10),
                            const Text('暂无预约记录',
                                style: TextStyle(color: AppColors.ink400)),
                          ],
                        ),
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
          color: AppColors.rose50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.rose200),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppColors.rose600, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(msg, style: const TextStyle(color: AppColors.rose600))),
        ]),
      );

  Widget _pendingBanner(int count) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.ink900,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33181B1B),
                blurRadius: 20,
                offset: Offset(0, 8),
                spreadRadius: -10),
          ],
        ),
        child: Row(
          children: [
            Pulse(
              child: Container(
                height: 34,
                width: 34,
                decoration: const BoxDecoration(
                    color: AppColors.accent500, shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active,
                    color: Colors.white, size: 19),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$count 条预约待处理',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  const Text('处理（通过 / 取消）后提醒才会消失',
                      style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                BackgroundPoller.silence();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已静音本轮提醒（未处理仍会再次提醒）')));
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('静音'),
            ),
          ],
        ),
      );

  Widget _statsGrid() {
    final s = _stats;
    final items = <(String, int, Color)>[
      ('总预约', s?.total ?? 0, AppColors.ink900),
      ('待处理', s?.booked ?? 0, AppColors.amber400),
      ('已通过', s?.verified ?? 0, AppColors.emerald500),
      ('已取消', s?.cancelled ?? 0, AppColors.ink300),
      ('今日预约', s?.today ?? 0, AppColors.accent500),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: items
          .map((it) => AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        height: 7,
                        width: 7,
                        decoration:
                            BoxDecoration(color: it.$3, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(it.$1,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.ink500)),
                    ]),
                    const SizedBox(height: 6),
                    AnimatedCount(it.$2,
                        style: const TextStyle(
                            color: AppColors.ink900,
                            fontSize: 26,
                            height: 1,
                            letterSpacing: -0.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }

  Widget _filterTabs() {
    Widget tab(String key, String label) {
      final active = _filter == key;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_filter == key) return;
            setState(() {
              _filter = key;
              _loading = true;
            });
            _refresh();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.ink900 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: active ? Colors.white : AppColors.ink500)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ink200),
      ),
      child: Row(children: [
        tab('booked', '待处理'),
        const SizedBox(width: 4),
        tab('all', '全部记录'),
      ]),
    );
  }

  Widget _bookingCard(Booking b) {
    final label = statusLabels[b.status] ?? b.status;
    final (Color bg, Color fg, Color dot) = switch (b.status) {
      'booked' => (AppColors.amber50, AppColors.amber700, AppColors.amber400),
      'verified' => (
          AppColors.emerald50,
          AppColors.emerald700,
          AppColors.emerald500
        ),
      _ => (AppColors.ink100, AppColors.ink500, AppColors.ink300),
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
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink900)),
                      const SizedBox(height: 2),
                      Text(b.phone,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.ink400)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: bg, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      height: 6,
                      width: 6,
                      decoration:
                          BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: fg)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _infoRow(Icons.meeting_room_outlined, b.resource.name),
            _infoRow(Icons.event_outlined,
                '${b.date}  ${b.slot.name} ${b.slot.range}'),
            _infoRow(Icons.groups_outlined,
                '${b.numPeople} 人 / ${b.quantity} 套${b.instructor.isNotEmpty ? '  ·  指导：${b.instructor}' : ''}'),
            if (b.description.isNotEmpty)
              _infoRow(Icons.notes_outlined, b.description),
            if (b.status == 'booked') ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TapScale(
                    child: _actionButton(
                      label: '通过',
                      icon: Icons.check_circle_outline,
                      bg: AppColors.emerald50,
                      fg: AppColors.emerald700,
                      onTap: () => _verify(b),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TapScale(
                    child: _actionButton(
                      label: '取消',
                      icon: Icons.cancel_outlined,
                      bg: Colors.white,
                      fg: AppColors.rose600,
                      border: AppColors.rose200,
                      onTap: () => _cancel(b),
                    ),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color bg,
    required Color fg,
    Color? border,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border ?? bg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      );

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.ink400),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.ink600))),
          ],
        ),
      );
}
