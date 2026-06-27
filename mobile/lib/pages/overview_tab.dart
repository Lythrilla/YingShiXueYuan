import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/ui.dart';

/// 数据概览：丰富统计卡片 + 近 14 天趋势 + 资源/时段分布。
class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  StatsReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    appRefresh.addListener(_onSignal);
  }

  @override
  void dispose() {
    appRefresh.removeListener(_onSignal);
    super.dispose();
  }

  void _onSignal() => _load();

  Future<void> _load() async {
    try {
      final api = await ApiClient.fromStore();
      final r = await api.statsReport();
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '无法连接服务器';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return RefreshIndicator(
      color: AppColors.ink900,
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.ink900))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_error != null) ErrorBanner(_error!),
                FadeSlideIn(child: _statsGrid(r)),
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: const SectionTitle('近 14 天预约趋势'),
                ),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: AppCard(
                    child: TrendChart(points: r?.trend ?? const []),
                  ),
                ),
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: const SectionTitle('资源预约分布'),
                ),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: AppCard(
                    child: BarList(
                        items: r?.byResource ?? const [],
                        color: AppColors.ink900),
                  ),
                ),
                const SizedBox(height: 18),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: const SectionTitle('时段预约分布'),
                ),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 200),
                  child: AppCard(
                    child: BarList(
                        items: r?.bySlot ?? const [],
                        color: AppColors.accent500),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statsGrid(StatsReport? r) {
    final items = <(String, int, Color)>[
      ('总预约', r?.total ?? 0, AppColors.ink900),
      ('待处理', r?.booked ?? 0, AppColors.amber400),
      ('已通过', r?.verified ?? 0, AppColors.emerald500),
      ('已取消', r?.cancelled ?? 0, AppColors.ink300),
      ('今日', r?.today ?? 0, AppColors.accent500),
      ('本周', r?.thisWeek ?? 0, AppColors.accent400),
      ('本月', r?.thisMonth ?? 0, AppColors.ink600),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        height: 7,
                        width: 7,
                        decoration: BoxDecoration(
                            color: it.$3, shape: BoxShape.circle),
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
                            fontSize: 24,
                            height: 1,
                            letterSpacing: -0.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ))
          .toList(),
    );
  }
}
