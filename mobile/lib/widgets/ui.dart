import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'anim.dart';

/// 区块标题（小号大写字母间距的灰色标签）。
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: AppColors.ink400)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 预约状态小胶囊。
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final label = statusLabels[status] ?? status;
    final (Color bg, Color fg, Color dot) = switch (status) {
      'booked' => (AppColors.amber50, AppColors.amber700, AppColors.amber400),
      'verified' => (
          AppColors.emerald50,
          AppColors.emerald700,
          AppColors.emerald500
        ),
      _ => (AppColors.ink100, AppColors.ink500, AppColors.ink300),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 6,
          width: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
      ]),
    );
  }
}

/// 图标 + 文本的信息行。
class InfoRow extends StatelessWidget {
  const InfoRow(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.ink400),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 13, color: AppColors.ink600))),
        ],
      ),
    );
  }
}

/// 空状态占位。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppColors.ink300),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: AppColors.ink400)),
          ],
        ),
      ),
    );
  }
}

/// 错误横幅。
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: Text(message,
                style: const TextStyle(color: AppColors.rose600))),
      ]),
    );
  }
}

/// 横向条形图：用于「按资源 / 按时段」的分布展示。
class BarList extends StatelessWidget {
  const BarList({super.key, required this.items, this.color});
  final List<LabeledCount> items;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('暂无数据', style: TextStyle(color: AppColors.ink400)),
      );
    }
    final maxVal =
        items.map((e) => e.value).fold<int>(1, (a, b) => a > b ? a : b);
    final c = color ?? AppColors.ink900;
    return Column(
      children: items.map((it) {
        final frac = maxVal == 0 ? 0.0 : it.value / maxVal;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(it.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.ink700)),
                  ),
                  Text('${it.value}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink900)),
                ],
              ),
              const SizedBox(height: 5),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: AppMotion.slow,
                curve: AppMotion.emphasized,
                builder: (_, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor: AppColors.ink100,
                    valueColor: AlwaysStoppedAnimation<Color>(c),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// 折线 / 柱状趋势图（近 N 天预约量），使用 CustomPaint 绘制，无第三方依赖。
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.height = 140});
  final List<LabeledCount> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
            child: Text('暂无趋势数据',
                style: TextStyle(color: AppColors.ink400))),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.slow,
      curve: AppMotion.emphasized,
      builder: (_, progress, _) => SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _TrendPainter(points, progress),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.points, this.progress);
  final List<LabeledCount> points;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final maxVal =
        points.map((e) => e.value).fold<int>(1, (a, b) => a > b ? a : b);
    final n = points.length;
    final gap = n > 1 ? size.width / (n - 1) : size.width;
    const bottomPad = 18.0;
    final chartH = size.height - bottomPad;

    final linePaint = Paint()
      ..color = AppColors.accent500
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final dotPaint = Paint()..color = AppColors.accent500;
    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33DB6238), Color(0x00DB6238)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartH));

    final grid = Paint()
      ..color = AppColors.ink100
      ..strokeWidth = 1;
    for (int i = 0; i <= 3; i++) {
      final y = chartH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    Offset at(int i) {
      final x = n > 1 ? gap * i : size.width / 2;
      final y = chartH - (points[i].value / maxVal) * (chartH - 6) - 3;
      return Offset(x, y);
    }

    final visible = <Offset>[at(0)];
    if (n > 1) {
      final scaled = (n - 1) * progress.clamp(0.0, 1.0);
      final fullLast = scaled.floor().clamp(0, n - 1).toInt();
      for (int i = 1; i <= fullLast; i++) {
        visible.add(at(i));
      }
      if (fullLast < n - 1) {
        final p0 = at(fullLast);
        final p1 = at(fullLast + 1);
        visible.add(Offset.lerp(p0, p1, (scaled - fullLast).toDouble())!);
      }
    }
    final path = Path()..moveTo(visible.first.dx, visible.first.dy);
    final fill = Path()
      ..moveTo(visible.first.dx, chartH)
      ..lineTo(visible.first.dx, visible.first.dy);
    for (final p in visible.skip(1)) {
      path.lineTo(p.dx, p.dy);
      fill.lineTo(p.dx, p.dy);
    }
    if (visible.length > 1) {
      fill
        ..lineTo(visible.last.dx, chartH)
        ..close();
      canvas.drawPath(fill, fillPaint);
      canvas.drawPath(path, linePaint);
    }

    final labelStyle = TextStyle(
        color: AppColors.ink400, fontSize: 9, fontWeight: FontWeight.w500);
    for (int i = 0; i < n; i++) {
      final threshold = n == 1 ? 0.0 : i / (n - 1);
      if (progress + 0.001 < threshold) continue;
      final p = at(i);
      canvas.drawCircle(p, 2.6, dotPaint);
      // 仅在首、中、尾绘制日期，避免拥挤。
      if (i == 0 || i == n - 1 || i == n ~/ 2) {
        final tp = TextPainter(
          text: TextSpan(text: _short(points[i].label), style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final dx = (p.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
        tp.paint(canvas, Offset(dx, chartH + 4));
      }
    }
  }

  String _short(String label) {
    // 期望 yyyy-MM-dd，截取 MM-dd。
    if (label.length >= 10 && label[4] == '-') return label.substring(5);
    return label;
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.points != points || old.progress != progress;
}
