import 'dart:convert';
import 'dart:typed_data';

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

  String get _root =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$_root$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// SSE 长连接地址（token 走查询参数，因为 EventSource/流式请求需要）。
  Uri sseUri() {
    final t = token;
    return _uri('/api/admin/events', t == null ? null : {'token': t});
  }

  /// 把后端返回的相对图片地址（/uploads/...）拼成可直接访问的完整地址。
  String absoluteUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_root$path';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, String> get authHeader => {
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
  Future<({String token, String username, String role})> login(
      String username, String password) async {
    final r = await http
        .post(_uri('/api/admin/login'),
            headers: _headers,
            body: jsonEncode({'username': username, 'password': password}))
        .timeout(_timeout);
    final j = _decode(r) as Map<String, dynamic>;
    return (
      token: j['token'] as String,
      username: j['username'] as String,
      role: (j['role'] ?? 'staff') as String,
    );
  }

  Future<({String username, String role})> me() async {
    final r =
        await http.get(_uri('/api/admin/me'), headers: _headers).timeout(_timeout);
    final j = _decode(r) as Map<String, dynamic>;
    return (
      username: (j['username'] ?? '') as String,
      role: (j['role'] ?? 'staff') as String,
    );
  }

  // ---------- bookings ----------
  Future<List<Booking>> bookings({
    String? status,
    String? keyword,
    int? resourceId,
    String? date,
  }) async {
    final q = <String, String>{};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (keyword != null && keyword.isNotEmpty) q['keyword'] = keyword;
    if (resourceId != null && resourceId > 0) {
      q['resource_id'] = resourceId.toString();
    }
    if (date != null && date.isNotEmpty) q['date'] = date;
    final r = await http
        .get(_uri('/api/admin/bookings', q), headers: _headers)
        .timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Booking>> pendingBookings() => bookings(status: 'booked');

  Future<void> verify(int id, {String note = ''}) async {
    final q = note.isEmpty ? null : {'note': note};
    final r = await http
        .post(_uri('/api/admin/bookings/$id/verify', q), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  Future<void> cancel(int id, {String note = ''}) async {
    final q = note.isEmpty ? null : {'note': note};
    final r = await http
        .post(_uri('/api/admin/bookings/$id/cancel', q), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  /// 彻底删除预约记录（不可恢复，区别于 cancel）。
  Future<void> deleteBooking(int id) async {
    final r = await http
        .delete(_uri('/api/admin/bookings/$id'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  /// 批量操作：op = 'verify' | 'cancel' | 'delete'。返回成功处理的条数。
  Future<int> batch(String op, List<int> ids, {String note = ''}) async {
    final r = await http
        .post(_uri('/api/admin/batch-bookings/$op'),
            headers: _headers, body: jsonEncode({'ids': ids, 'note': note}))
        .timeout(_timeout);
    final j = _decode(r) as Map<String, dynamic>;
    return _asIntField(j['processed']);
  }

  // ---------- stats ----------
  Future<Stats> stats() async {
    final r = await http
        .get(_uri('/api/admin/stats'), headers: _headers)
        .timeout(_timeout);
    return Stats.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<StatsReport> statsReport() async {
    final r = await http
        .get(_uri('/api/admin/stats/report'), headers: _headers)
        .timeout(_timeout);
    return StatsReport.fromJson(_decode(r) as Map<String, dynamic>);
  }

  // ---------- resources ----------
  Future<List<Resource>> resources() async {
    final r = await http
        .get(_uri('/api/admin/resources'), headers: _headers)
        .timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list
        .map((e) => Resource.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Resource> createResource(Map<String, dynamic> body) async {
    final r = await http
        .post(_uri('/api/admin/resources'),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return Resource.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<Resource> updateResource(int id, Map<String, dynamic> body) async {
    final r = await http
        .put(_uri('/api/admin/resources/$id'),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return Resource.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<void> deleteResource(int id) async {
    final r = await http
        .delete(_uri('/api/admin/resources/$id'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  /// 上传图片，返回可访问的 url。
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', _uri('/api/admin/uploads/images'))
      ..headers.addAll(authHeader)
      ..files
          .add(http.MultipartFile.fromBytes('image', bytes, filename: filename));
    final streamed = await req.send().timeout(_timeout);
    final r = await http.Response.fromStream(streamed);
    final j = _decode(r) as Map<String, dynamic>;
    return (j['url'] ?? '') as String;
  }

  // ---------- slots ----------
  Future<List<Slot>> slots() async {
    final r = await http
        .get(_uri('/api/admin/slots'), headers: _headers)
        .timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list.map((e) => Slot.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Slot> createSlot(Map<String, dynamic> body) async {
    final r = await http
        .post(_uri('/api/admin/slots'), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return Slot.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<Slot> updateSlot(int id, Map<String, dynamic> body) async {
    final r = await http
        .put(_uri('/api/admin/slots/$id'),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    return Slot.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<void> deleteSlot(int id) async {
    final r = await http
        .delete(_uri('/api/admin/slots/$id'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  // ---------- admins ----------
  Future<List<Admin>> admins() async {
    final r = await http
        .get(_uri('/api/admin/admins'), headers: _headers)
        .timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list.map((e) => Admin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Admin> createAdmin(String username, String password, String role) async {
    final r = await http
        .post(_uri('/api/admin/admins'),
            headers: _headers,
            body: jsonEncode(
                {'username': username, 'password': password, 'role': role}))
        .timeout(_timeout);
    return Admin.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<void> updateAdmin(int id, Map<String, dynamic> body) async {
    final r = await http
        .put(_uri('/api/admin/admins/$id'),
            headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    _decode(r);
  }

  Future<void> deleteAdmin(int id) async {
    final r = await http
        .delete(_uri('/api/admin/admins/$id'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  // ---------- duty shifts（排班） ----------
  Future<List<DutyShift>> shifts() async {
    final r = await http
        .get(_uri('/api/admin/shifts'), headers: _headers)
        .timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list
        .map((e) => DutyShift.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<DutyShift> createShift({
    required int weekday,
    required int slotId,
    required int resourceId,
    required String adminUsername,
  }) async {
    final r = await http
        .post(_uri('/api/admin/shifts'),
            headers: _headers,
            body: jsonEncode({
              'weekday': weekday,
              'slot_id': slotId,
              'resource_id': resourceId,
              'admin_username': adminUsername,
            }))
        .timeout(_timeout);
    return DutyShift.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<void> deleteShift(int id) async {
    final r = await http
        .delete(_uri('/api/admin/shifts/$id'), headers: _headers)
        .timeout(_timeout);
    _decode(r);
  }

  // ---------- export ----------
  /// 导出预约为 Excel（xlsx）字节流，可按筛选条件过滤。
  Future<Uint8List> exportBookings({
    String? status,
    String? keyword,
    int? resourceId,
    String? date,
  }) async {
    final q = <String, String>{};
    if (status != null && status.isNotEmpty) q['status'] = status;
    if (keyword != null && keyword.isNotEmpty) q['keyword'] = keyword;
    if (resourceId != null && resourceId > 0) {
      q['resource_id'] = resourceId.toString();
    }
    if (date != null && date.isNotEmpty) q['date'] = date;
    final r = await http
        .get(_uri('/api/admin/export', q), headers: authHeader)
        .timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) _fail(r);
    return r.bodyBytes;
  }

  // ---------- operation logs ----------
  Future<List<OperationLog>> logs({int limit = 200}) async {
    final r = await http
        .get(_uri('/api/admin/logs', {'limit': limit.toString()}),
            headers: _headers)
        .timeout(_timeout);
    final list = _decode(r) as List<dynamic>;
    return list
        .map((e) => OperationLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

int _asIntField(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
