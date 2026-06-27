import 'package:flutter/foundation.dart';

/// 全局刷新信号：后台收到审批类事件时自增，各页面监听后即时重载。
final ValueNotifier<int> appRefresh = ValueNotifier<int>(0);

void bumpRefresh() => appRefresh.value++;
