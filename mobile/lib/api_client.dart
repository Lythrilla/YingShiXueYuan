import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// 对接后端 `/api/admin/*` 接口的轻量客户端。
class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  final String baseUrl;
  final String? token;

  static Future<ApiClient> fromStore() async {
    return ApiClient(
      baseUrl: await Store.serverUrl(),
      token: await Store.token(),
    );
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Never _fail(http.Response r) {
    String msg = '请求失败 (${r.statusCode})';
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is Map && body['message'] is String) {
        msg = body['message'] as String;
      } else if (body is Map && body['error'] is String) {
        msg = body['error'] as String;
      }
    } catch (_) {}
    throw ApiException(msg, statusCode: r.statusCode);
  }

  dynamic _decode(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) _fail(r);
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static const _timeout = Duration(seconds: 15);

  // ---------- auth ----------
  Future<({String token, String username})> login(
      String username, String password) async {
    final r = await http
        .post(_uri('/api/admin/login'),
            headers: _headers,
            body: jsonEncode({'username': username, 'password': password}))
        .timeout(_timeout);
    final j = _decode(r) as Map<String, dynamic>;
    return (token: j['token'] as String, username: j['username'] as String);
  }

  // ---------- bookings ----------
  Future<List<Booking>> bookings({String? status, String? keyword}) async {
    final q = <String, String>{};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (keyword != null && keyword.isNotEmpty) q['keyword'] = keyword;
    final r =
        await http.get(_uri('/api/admin/bookings', q), headers: _headers).timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Booking>> pendingBookings() => bookings(status: 'booked');

  Future<void> verify(int id) async {
    final r = await http
        .post(_uri('/api/admin/bookings/$id/verify'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  Future<void> cancel(int id) async {
    final r = await http
        .post(_uri('/api/admin/bookings/$id/cancel'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  Future<Stats> stats() async {
    final r =
        await http.get(_uri('/api/admin/stats'), headers: _headers).timeout(_timeout);
    return Stats.fromJson(_decode(r) as Map<String, dynamic>);
  }
}
