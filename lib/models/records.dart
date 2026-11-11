/// How a worker is paid. Files written before 1.0.5 have no pay type and
/// are read as [daily].
enum PayType {
  daily('daily', '日当'),
  hourly('hourly', '時給'),
  monthly('monthly', '月給');

  const PayType(this.key, this.label);

  /// Stored in JSON. Never rename.
  final String key;

  /// 日当 / 時給 / 月給.
  final String label;

  static PayType fromKey(Object? raw) {
    for (final type in values) {
      if (type.key == raw) return type;
    }
    return daily;
  }
}

/// `日当 ¥18,000`, `時給 ¥1,500` or `月給 ¥300,000`.
String payLabel(Worker worker) {
  final digits = worker.rate.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${worker.payType.label} ¥$digits';
}

/// Working hours for one full day (1人工) of an hourly worker.
const defaultWorkHours = 8.0;

/// A person who goes to sites: the user, a crew member, or a helper.
class Worker {
  const Worker({
    required this.id,
    required this.name,
    required this.dayRate,
    required this.overtimeRate,
    required this.createdAt,
    this.payType = PayType.daily,
    this.hourlyRate = 0,
    this.monthlySalary = 0,
  });

  final String id;
  final String name;
  final PayType payType;

  /// 日当 in yen for one full day (1人工). Used when [payType] is daily.
  final int dayRate;

  /// 時給 in yen per working hour. Used when [payType] is hourly.
  final int hourlyRate;

  /// 月給 in yen, counted once for each month with attendance.
  final int monthlySalary;

  /// 残業単価 in yen per hour. Zero when overtime is not paid.
  final int overtimeRate;
  final DateTime createdAt;

  /// The rate for [payType], for example `日当 ¥18,000`.
  int get rate => switch (payType) {
    PayType.daily => dayRate,
    PayType.hourly => hourlyRate,
    PayType.monthly => monthlySalary,
  };

  Worker copyWith({
    String? name,
    int? dayRate,
    int? overtimeRate,
    PayType? payType,
    int? hourlyRate,
    int? monthlySalary,
  }) {
    return Worker(
      id: id,
      name: name ?? this.name,
      dayRate: dayRate ?? this.dayRate,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      createdAt: createdAt,
      payType: payType ?? this.payType,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      monthlySalary: monthlySalary ?? this.monthlySalary,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'payType': payType.key,
    'dayRate': dayRate,
    'hourlyRate': hourlyRate,
    'monthlySalary': monthlySalary,
    'overtimeRate': overtimeRate,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static Worker fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      payType: PayType.fromKey(json['payType']),
      dayRate: _int(json['dayRate']),
      hourlyRate: _int(json['hourlyRate']),
      monthlySalary: _int(json['monthlySalary']),
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
/// The pay type and rates are copied in when the record is made, so a later
/// raise does not rewrite months that were already paid.
class DayRecord {
  const DayRecord({
    required this.workerId,
    required this.day,
    required this.siteId,
    required this.units,
    required this.overtimeHours,
    required this.dayRate,
    required this.overtimeRate,
    this.payType = PayType.daily,
    this.hours = 0,
    this.hourlyRate = 0,
    this.monthlySalary = 0,
  });

  final PayType payType;

  /// Working hours (not overtime). Used when [payType] is hourly.
  final double hours;
  final int hourlyRate;

  /// The worker's 月給 at the time. Not part of [amount]; the month summary
  /// adds it once per worker.
  final int monthlySalary;

  final String workerId;

  /// `YYYY-MM-DD`, see `dayKey`.
  final String day;
  final String siteId;

  /// 人工: 1.0 for a full day, 0.5 for a half day.
  final double units;
  final double overtimeHours;
  final int dayRate;
  final int overtimeRate;

  int get overtimeAmount => (overtimeRate * overtimeHours).round();

  /// Pay for this day. 日当: 人工 x 日当. 時給: hours x 時給. 月給: none here
  /// (the salary is added once per month). Overtime is added for every type
  /// when a 残業単価 is set.
  int get amount {
    final base = switch (payType) {
      PayType.daily => (dayRate * units).round(),
      PayType.hourly => (hourlyRate * hours).round(),
      PayType.monthly => 0,
    };
    return base + overtimeAmount;
  }

  DayRecord copyWith({
    String? siteId,
    double? units,
    double? overtimeHours,
    int? dayRate,
    int? overtimeRate,
    PayType? payType,
    double? hours,
    int? hourlyRate,
    int? monthlySalary,
  }) {
    return DayRecord(
      workerId: workerId,
      day: day,
      siteId: siteId ?? this.siteId,
      units: units ?? this.units,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      dayRate: dayRate ?? this.dayRate,
      overtimeRate: overtimeRate ?? this.overtimeRate,
      payType: payType ?? this.payType,
      hours: hours ?? this.hours,
      hourlyRate: hourlyRate ?? this.hourlyRate,
      monthlySalary: monthlySalary ?? this.monthlySalary,
    );
  }

  Map<String, dynamic> toJson() => {
    'workerId': workerId,
    'day': day,
    'siteId': siteId,
    'payType': payType.key,
    'units': units,
    'hours': hours,
    'overtimeHours': overtimeHours,
    'dayRate': dayRate,
    'hourlyRate': hourlyRate,
    'monthlySalary': monthlySalary,
    'overtimeRate': overtimeRate,
  };

  static DayRecord fromJson(Map<String, dynamic> json) {
    return DayRecord(
      workerId: json['workerId'] as String,
      day: json['day'] as String,
      siteId: (json['siteId'] as String?) ?? '',
      payType: PayType.fromKey(json['payType']),
      units: _double(json['units'], fallback: 1),
      hours: _double(json['hours']),
      overtimeHours: _double(json['overtimeHours']),
      dayRate: _int(json['dayRate']),
      hourlyRate: _int(json['hourlyRate']),
      monthlySalary: _int(json['monthlySalary']),
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
