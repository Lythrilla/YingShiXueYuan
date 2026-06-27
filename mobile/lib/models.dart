// 与后端 `backend/src/models.rs` 对应的数据模型。

class Resource {
  Resource({
    required this.id,
    required this.name,
    required this.kind,
    required this.description,
    required this.totalQuantity,
  });

  final int id;
  final String name;
  final String kind; // 'lab' | 'equipment'
  final String description;
  final int totalQuantity;

  factory Resource.fromJson(Map<String, dynamic> j) => Resource(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        kind: (j['kind'] ?? 'lab') as String,
        description: (j['description'] ?? '') as String,
        totalQuantity: (j['total_quantity'] ?? 1) as int,
      );
}

class Slot {
  Slot({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
  });

  final int id;
  final String name;
  final String startTime;
  final String endTime;

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        id: j['id'] as int,
        name: (j['name'] ?? '') as String,
        startTime: (j['start_time'] ?? '') as String,
        endTime: (j['end_time'] ?? '') as String,
      );

  String get range => '$startTime-$endTime';
}

class Booking {
  Booking({
    required this.id,
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
    required this.resource,
    required this.slot,
  });

  final int id;
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
  final Resource resource;
  final Slot slot;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
        id: j['id'] as int,
        date: (j['date'] ?? '') as String,
        applicantName: (j['applicant_name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        major: (j['major'] ?? '') as String,
        numPeople: (j['num_people'] ?? 1) as int,
        instructor: (j['instructor'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        quantity: (j['quantity'] ?? 1) as int,
        status: (j['status'] ?? 'booked') as String,
        createdAt: (j['created_at'] ?? '') as String,
        verifiedAt: j['verified_at'] as String?,
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
        total: (j['total'] ?? 0) as int,
        booked: (j['booked'] ?? 0) as int,
        verified: (j['verified'] ?? 0) as int,
        cancelled: (j['cancelled'] ?? 0) as int,
        today: (j['today'] ?? 0) as int,
      );
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
