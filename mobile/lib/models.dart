// 与后端 `backend/src/models.rs` 对应的数据模型。

int _asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _asBool(dynamic v, [bool fallback = true]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

class Resource {
  Resource({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    required this.imageUrl,
    required this.totalQuantity,
    required this.individualBookable,
    required this.sortOrder,
    required this.isActive,
    required this.manager,
  });

  final int id;
  final String name;
  final String kind; // 'lab' | 'equipment'
  final String description;
  final String imageUrl;
  final int totalQuantity;
  final bool individualBookable;
  final int sortOrder;
  final bool isActive;
  final String manager; // 默认负责人（开门人）用户名

  factory Resource.fromJson(Map<String, dynamic> j) => Resource(
        id: _asInt(j['id']),
        name: (j['name'] ?? '') as String,
        kind: (j['kind'] ?? 'lab') as String,
        description: (j['description'] ?? '') as String,
        imageUrl: (j['image_url'] ?? '') as String,
        totalQuantity: _asInt(j['total_quantity'], 1),
        individualBookable: _asBool(j['individual_bookable']),
        sortOrder: _asInt(j['sort_order']),
        isActive: _asBool(j['is_active']),
        manager: (j['manager'] ?? '') as String,
      );

  String get kindLabel => kind == 'equipment' ? '设备' : '实验室';
}

class Slot {
  Slot({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.sortOrder,
    required this.isActive,
  });

  final int id;
  final String name;
  final String startTime;
  final String endTime;
  final int sortOrder;
  final bool isActive;

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        id: _asInt(j['id']),
        name: (j['name'] ?? '') as String,
        startTime: (j['start_time'] ?? '') as String,
        endTime: (j['end_time'] ?? '') as String,
        sortOrder: _asInt(j['sort_order']),
        isActive: _asBool(j['is_active']),
      );

  String get range => '$startTime-$endTime';
}

class Booking {
  Booking({
    required this.id,
    required this.resourceId,
    required this.slotId,
    required this.date,
    required this.applicantName,
    required this.phone,
    required this.major,
    required this.numPeople,
    required this.instructor,
    required this.description,
    required this.quantity,
    required this.status,
    required this.createdAt,
    required this.verifiedAt,
    required this.adminNote,
    required this.processedBy,
    required this.resource,
    required this.slot,
  });

  final int id;
  final int resourceId;
  final int slotId;
  final String date;
  final String applicantName;
  final String phone;
  final String major;
  final int numPeople;
  final String instructor;
  final String description;
  final int quantity;
  final String status; // booked | verified | cancelled
  final String createdAt;
  final String? verifiedAt;
  final String adminNote;
  final String processedBy;
  final Resource resource;
  final Slot slot;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: _asInt(j['id']),
        resourceId: _asInt(j['resource_id']),
        slotId: _asInt(j['slot_id']),
        date: (j['date'] ?? '') as String,
        applicantName: (j['applicant_name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        major: (j['major'] ?? '') as String,
        numPeople: _asInt(j['num_people'], 1),
        instructor: (j['instructor'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        quantity: _asInt(j['quantity'], 1),
        status: (j['status'] ?? 'booked') as String,
        createdAt: (j['created_at'] ?? '') as String,
        verifiedAt: j['verified_at'] as String?,
        adminNote: (j['admin_note'] ?? '') as String,
        processedBy: (j['processed_by'] ?? '') as String,
        resource: Resource.fromJson(j['resource'] as Map<String, dynamic>),
        slot: Slot.fromJson(j['slot'] as Map<String, dynamic>),
      );

  bool get isPending => status == 'booked';

  String get summary =>
      '$applicantName · ${resource.name} · $date ${slot.range}';
}

class Stats {
  Stats({
    required this.total,
    required this.booked,
    required this.verified,
    required this.cancelled,
    required this.today,
  });

  final int total;
  final int booked;
  final int verified;
  final int cancelled;
  final int today;

  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
        total: _asInt(j['total']),
        booked: _asInt(j['booked']),
        verified: _asInt(j['verified']),
        cancelled: _asInt(j['cancelled']),
        today: _asInt(j['today']),
      );
}

class LabeledCount {
  LabeledCount({required this.label, required this.value});
  final String label;
  final int value;

  factory LabeledCount.fromJson(Map<String, dynamic> j) => LabeledCount(
        label: (j['label'] ?? '') as String,
        value: _asInt(j['value']),
      );
}

/// 与后端 StatsReport 对应的丰富统计报表。
class StatsReport {
  StatsReport({
    required this.total,
    required this.booked,
    required this.verified,
    required this.cancelled,
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.trend,
    required this.byResource,
    required this.bySlot,
  });

  final int total;
  final int booked;
  final int verified;
  final int cancelled;
  final int today;
  final int thisWeek;
  final int thisMonth;
  final List<LabeledCount> trend;
  final List<LabeledCount> byResource;
  final List<LabeledCount> bySlot;

  factory StatsReport.fromJson(Map<String, dynamic> j) {
    List<LabeledCount> arr(dynamic v) => (v as List<dynamic>? ?? const [])
        .map((e) => LabeledCount.fromJson(e as Map<String, dynamic>))
        .toList();
    return StatsReport(
      total: _asInt(j['total']),
      booked: _asInt(j['booked']),
      verified: _asInt(j['verified']),
      cancelled: _asInt(j['cancelled']),
      today: _asInt(j['today']),
      thisWeek: _asInt(j['this_week']),
      thisMonth: _asInt(j['this_month']),
      trend: arr(j['trend']),
      byResource: arr(j['by_resource']),
      bySlot: arr(j['by_slot']),
    );
  }

  Stats get base => Stats(
        total: total,
        booked: booked,
        verified: verified,
        cancelled: cancelled,
        today: today,
      );
}

class Admin {
  Admin({
    required this.id,
    required this.username,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  final int id;
  final String username;
  final String role; // super | staff
  final bool isActive;
  final String createdAt;

  bool get isSuper => role == 'super';
  String get roleLabel => isSuper ? '超级管理员' : '普通管理员';

  factory Admin.fromJson(Map<String, dynamic> j) => Admin(
        id: _asInt(j['id']),
        username: (j['username'] ?? '') as String,
        role: (j['role'] ?? 'staff') as String,
        isActive: _asBool(j['is_active']),
        createdAt: (j['created_at'] ?? '') as String,
      );
}

class OperationLog {
  OperationLog({
    required this.id,
    required this.actor,
    required this.action,
    required this.target,
    required this.detail,
    required this.createdAt,
  });

  final int id;
  final String actor;
  final String action;
  final String target;
  final String detail;
  final String createdAt;

  factory OperationLog.fromJson(Map<String, dynamic> j) => OperationLog(
        id: _asInt(j['id']),
        actor: (j['actor'] ?? '') as String,
        action: (j['action'] ?? '') as String,
        target: (j['target'] ?? '') as String,
        detail: (j['detail'] ?? '') as String,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

/// 排班：星期 + 时段 + 资源 + 负责人（开门人）。
class DutyShift {
  DutyShift({
    required this.id,
    required this.weekday,
    required this.slotId,
    required this.resourceId,
    required this.adminUsername,
    required this.createdAt,
  });

  final int id;
  final int weekday; // -1=每天, 0=周日..6=周六
  final int slotId; // 0=全部时段
  final int resourceId; // 0=全部资源
  final String adminUsername;
  final String createdAt;

  factory DutyShift.fromJson(Map<String, dynamic> j) => DutyShift(
        id: _asInt(j['id']),
        weekday: _asInt(j['weekday'], -1),
        slotId: _asInt(j['slot_id']),
        resourceId: _asInt(j['resource_id']),
        adminUsername: (j['admin_username'] ?? '') as String,
        createdAt: (j['created_at'] ?? '') as String,
      );
}

const weekdayLabels = <String>['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

String weekdayLabel(int weekday) {
  if (weekday < 0) return '每天';
  if (weekday >= 0 && weekday <= 6) return weekdayLabels[weekday];
  return '未知';
}

/// SSE 推送的「开门提醒」事件。
class DoorReminder {
  DoorReminder({
    required this.bookingId,
    required this.resource,
    required this.slot,
    required this.startTime,
    required this.date,
    required this.applicant,
    required this.duty,
  });

  final int bookingId;
  final String resource;
  final String slot;
  final String startTime;
  final String date;
  final String applicant;
  final String duty; // 负责人；为空表示通知所有管理员

  factory DoorReminder.fromJson(Map<String, dynamic> j) => DoorReminder(
        bookingId: _asInt(j['booking_id']),
        resource: (j['resource'] ?? '') as String,
        slot: (j['slot'] ?? '') as String,
        startTime: (j['start_time'] ?? '') as String,
        date: (j['date'] ?? '') as String,
        applicant: (j['applicant'] ?? '') as String,
        duty: (j['duty'] ?? '') as String,
      );

  String get dutyLabel => duty.isEmpty ? '全体管理员' : duty;

  String get title => '该去开门了：$resource';

  String get body =>
      '$date $slot（$startTime 开始）· 申请人 $applicant · 负责人 $dutyLabel';
}

class StatusMeta {
  const StatusMeta(this.label);
  final String label;
}

const statusLabels = <String, String>{
  'booked': '待处理',
  'verified': '已通过',
  'cancelled': '已取消',
};
