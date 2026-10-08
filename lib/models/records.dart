/// A person who goes to sites: the user, a crew member, or a helper.
class Worker {
  const Worker({
    required this.id,
    required this.name,
    required this.dayRate,
    required this.overtimeRate,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// 日当 in yen for one full day (1人工).
  final int dayRate;

  /// 残業単価 in yen per hour. Zero when overtime is not paid.
  final int overtimeRate;
  final DateTime createdAt;

  Worker copyWith({String? name, int? dayRate, int? overtimeRate}) {
    return Worker(
      id: id,
      name: name ?? this.name,
      dayRate: dayRate ?? this.dayRate,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dayRate': dayRate,
    'overtimeRate': overtimeRate,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static Worker fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      dayRate: _int(json['dayRate']),
      overtimeRate: _int(json['overtimeRate']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(_int(json['createdAt'])),
    );
  }
}

class Site {
  const Site({
    required this.id,
    required this.name,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Free text such as the general contractor (元請) name.
  final String note;
  final DateTime createdAt;

  Site copyWith({String? name, String? note}) {
    return Site(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static Site fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(_int(json['createdAt'])),
    );
  }
}

/// One worker on one day (出面). A worker has at most one record per day.
///
/// The day rate and overtime rate are copied in when the record is made, so
/// a later raise does not rewrite months that were already paid.
class DayRecord {
  const DayRecord({
    required this.workerId,
    required this.day,
    required this.siteId,
    required this.units,
    required this.overtimeHours,
    required this.dayRate,
    required this.overtimeRate,
  });

  final String workerId;

  /// `YYYY-MM-DD`, see `dayKey`.
  final String day;
  final String siteId;

  /// 人工: 1.0 for a full day, 0.5 for a half day.
  final double units;
  final double overtimeHours;
  final int dayRate;
  final int overtimeRate;

  int get amount =>
      (dayRate * units).round() + (overtimeRate * overtimeHours).round();

  DayRecord copyWith({
    String? siteId,
    double? units,
    double? overtimeHours,
    int? dayRate,
    int? overtimeRate,
  }) {
    return DayRecord(
      workerId: workerId,
      day: day,
      siteId: siteId ?? this.siteId,
      units: units ?? this.units,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      dayRate: dayRate ?? this.dayRate,
      overtimeRate: overtimeRate ?? this.overtimeRate,
    );
  }

  Map<String, dynamic> toJson() => {
    'workerId': workerId,
    'day': day,
    'siteId': siteId,
    'units': units,
    'overtimeHours': overtimeHours,
    'dayRate': dayRate,
    'overtimeRate': overtimeRate,
  };

  static DayRecord fromJson(Map<String, dynamic> json) {
    return DayRecord(
      workerId: json['workerId'] as String,
      day: json['day'] as String,
      siteId: (json['siteId'] as String?) ?? '',
      units: _double(json['units'], fallback: 1),
      overtimeHours: _double(json['overtimeHours']),
      dayRate: _int(json['dayRate']),
      overtimeRate: _int(json['overtimeRate']),
    );
  }
}

int _int(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}

double _double(Object? raw, {double fallback = 0}) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}
