import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 极简 SSE（Server-Sent Events）客户端：保持一条空闲长连接，
/// 服务器有事件时即时推送，断线自动重连。替代高频轮询，省电且实时。
class SseClient {
  SseClient({required this.uri, required this.onEvent, this.onState});

  final Uri uri;
  final void Function(Map<String, dynamic> data) onEvent;
  final void Function(bool connected)? onState;

  http.Client? _client;
  StreamSubscription<String>? _sub;
  bool _stopped = false;
  Timer? _retry;
  int _backoffSeconds = 1;

  void start() {
    _stopped = false;
    _connect();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    _client?.close();
    _client = http.Client();
    try {
      final req = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['Cache-Control'] = 'no-cache';
      final resp = await _client!.send(req);
      if (resp.statusCode != 200) {
        throw Exception('SSE status ${resp.statusCode}');
      }
      onState?.call(true);
      _backoffSeconds = 1;

      final buffer = StringBuffer();
      _sub = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          // 事件以空行分隔；这里只取 data: 字段（后端每条事件就是一行 JSON）。
          if (line.startsWith('data:')) {
            buffer.write(line.substring(5).trimLeft());
          } else if (line.isEmpty) {
            final payload = buffer.toString();
            buffer.clear();
            _dispatch(payload);
          }
        },
        onError: (Object e) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('SSE connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _dispatch(String payload) {
    if (payload.isEmpty || payload == 'ping') return;
    try {
      final obj = jsonDecode(payload);
      if (obj is Map<String, dynamic>) onEvent(obj);
    } catch (_) {
      // 忽略非 JSON 的保活/注释行。
    }
  }

  void _scheduleReconnect() {
    onState?.call(false);
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    if (_stopped) return;
    _retry?.cancel();
    final wait = _backoffSeconds;
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
    _retry = Timer(Duration(seconds: wait), _connect);
  }

  void stop() {
    _stopped = true;
    _retry?.cancel();
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
    onState?.call(false);
  }
}
