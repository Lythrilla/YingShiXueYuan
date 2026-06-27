import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppMotion {
  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 520);

  static const standard = Curves.easeOutCubic;
  static const emphasized = Cubic(0.2, 0, 0, 1);
}

/// 入场动画：淡入 + 上浮，可设置延迟，用于做列表 stagger 效果。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.slow,
    this.offset = 18,
    this.scaleBegin = 0.98,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final double scaleBegin;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _c,
    curve: AppMotion.emphasized,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _curve,
      builder: (_, child) => Opacity(
        opacity: _curve.value,
        child: Transform.scale(
          scale: widget.scaleBegin + (1 - widget.scaleBegin) * _curve.value,
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _curve.value)),
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

/// 数字滚动动画（统计卡用）。
class AnimatedCount extends StatelessWidget {
  const AnimatedCount(
    this.value, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.emphasized,
      builder: (_, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// 循环缩放脉冲（待处理横幅的提醒图标用）。
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.child,
    this.min = 0.85,
    this.max = 1.15,
  });
  final Widget child;
  final double min;
  final double max;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return widget.child;
    }
    return ScaleTransition(
      scale: Tween(
        begin: widget.min,
        end: widget.max,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// 带按压缩放反馈的点击包装。
class TapScale extends StatefulWidget {
  const TapScale({
    super.key,
    required this.child,
    this.onTap,
    this.enableFeedback = true,
  });
  final Widget child;
  final VoidCallback? onTap;
  final bool enableFeedback;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  double _scale = 1;

  void _handleTap() {
    if (widget.enableFeedback) HapticFeedback.selectionClick();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return GestureDetector(
        onTap: widget.onTap == null ? null : _handleTap,
        child: widget.child,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => setState(() => _scale = 0.96),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap == null ? null : _handleTap,
      child: AnimatedScale(
        scale: _scale,
        duration: AppMotion.fast,
        curve: AppMotion.emphasized,
        child: widget.child,
      ),
    );
  }
}

class AnimatedIndexedStack extends StatelessWidget {
  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotion.medium,
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if ((MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return IndexedStack(index: index, children: children);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          IgnorePointer(
            ignoring: i != index,
            child: AnimatedOpacity(
              opacity: i == index ? 1 : 0,
              duration: duration,
              curve: AppMotion.standard,
              child: AnimatedSlide(
                offset: i == index ? Offset.zero : const Offset(0, 0.015),
                duration: duration,
                curve: AppMotion.emphasized,
                child: TickerMode(enabled: i == index, child: children[i]),
              ),
            ),
          ),
      ],
    );
  }
}

/// 统一的页面切换过渡：淡入 + 轻微上滑。
Route<T> fadeThroughRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: AppMotion.medium,
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
