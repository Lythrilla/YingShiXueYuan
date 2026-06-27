import 'package:flutter/foundation.dart';

/// 全局刷新信号：后台 SSE 收到审批类事件时自增，各页面监听后即时重载。
final ValueNotifier<int> appRefresh = ValueNotifier<int>(0);

/// SSE 长连接状态（true=已连上实时推送）。
final ValueNotifier<bool> appConnected = ValueNotifier<bool>(false);

void bumpRefresh() => appRefresh.value++;
