import '../ids.dart';

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

/// Who the roster entry is. Files written before 1.0.6 have no kind and are
/// read as [employee].
enum WorkerKind {
  employee('employee', '従業員'),
  contractor('contractor', '外注');

  const WorkerKind(this.key, this.label);

  /// Stored in JSON. Never rename.
  final String key;
  final String label;

  static WorkerKind fromKey(Object? raw) {
    for (final kind in values) {
      if (kind.key == raw) return kind;
    }
    return employee;
  }
}

/// 昼 or 夜勤 of one entry. Files written before 1.0.6 are all 昼.
enum Shift {
  day('day', '昼'),
  night('night', '夜勤');

  const Shift(this.key, this.label);

  /// Stored in JSON. Never rename.
  final String key;
  final String label;

  static Shift fromKey(Object? raw) {
    for (final shift in values) {
      if (shift.key == raw) return shift;
    }
    return day;
  }
}

/// Most 人工 one entry can hold (a 外注 crew).
const maxUnitsPerRecord = 99.0;

/// `日当 ¥18,000`, `時給 ¥1,500` or `月給 ¥300,000`. A 外注 paid per 人工 reads
/// `単価 ¥18,000`.
String payLabel(Worker worker) {
  final digits = worker.rate.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${worker.payName} ¥$digits';
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
    this.kind = WorkerKind.employee,
  });

  final String id;
  final String name;
  final PayType payType;

  /// 従業員 or 外注（会社）.
  final WorkerKind kind;

  /// `日当`, `時給`, `月給`; `単価` for a 外注 paid per 人工.
  String get payName =>
      kind == WorkerKind.contractor && payType == PayType.daily
      ? '単価'
      : payType.label;

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
    WorkerKind? kind,
  }) {
    return Worker(
      id: id,
      kind: kind ?? this.kind,
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
    'kind': kind.key,
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
      kind: WorkerKind.fromKey(json['kind']),
      payType: PayType.fromKey(json['payType']),
      dayRate: _int(json['dayRate']),
      hourlyRate: _int(json['hourlyRate']),
      monthlySalary: _int(json['monthlySalary']),
      overtimeRate: _int(json['overtimeRate']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(_int(json['createdAt'])),
    );
  }
}

/// How a 平米 site's lump sum is entered. Files before 1.0.7 are not
/// 平米 sites.
enum AreaAmountMode {
  areaTimesRate('areaTimesRate'),
  contract('contract');

  const AreaAmountMode(this.key);
  final String key;

  static AreaAmountMode fromKey(Object? raw) {
    for (final mode in values) {
      if (mode.key == raw) return mode;
    }
    return areaTimesRate;
  }
}

class Site {
  const Site({
    required this.id,
    required this.name,
    required this.note,
    required this.createdAt,
    this.isAreaSite = false,
    this.areaAmountMode = AreaAmountMode.areaTimesRate,
    this.areaSqm = 0,
    this.areaUnitPrice = 0,
    this.contractAmount = 0,
    this.settlementMonth = '',
  });

  final String id;
  final String name;

  /// Free text such as the general contractor (元請) name.
  final String note;
  final DateTime createdAt;

  /// When true, this site pays a lump 平米/請負 amount and no 日当.
  final bool isAreaSite;

  /// 平米数×単価, or a single 請負額.
  final AreaAmountMode areaAmountMode;

  /// 平米数. Used when [areaAmountMode] is [AreaAmountMode.areaTimesRate].
  final double areaSqm;

  /// 平米単価 in yen. Used with [areaSqm].
  final int areaUnitPrice;

  /// 請負額 in yen. Used when [areaAmountMode] is [AreaAmountMode.contract].
  final int contractAmount;

  /// `YYYY-MM`. The lump amount is counted only in this month, split by
  /// 人工 across every month of the job. Empty means not yet settled.
  final String settlementMonth;

  /// Lump sum to split, or 0 when this is not a 平米 site.
  int get areaTotal {
    if (!isAreaSite) return 0;
    if (areaAmountMode == AreaAmountMode.contract) return contractAmount;
    return (areaSqm * areaUnitPrice).round();
  }

  Site copyWith({
    String? name,
    String? note,
    bool? isAreaSite,
    AreaAmountMode? areaAmountMode,
    double? areaSqm,
    int? areaUnitPrice,
    int? contractAmount,
    String? settlementMonth,
  }) {
    return Site(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      createdAt: createdAt,
      isAreaSite: isAreaSite ?? this.isAreaSite,
      areaAmountMode: areaAmountMode ?? this.areaAmountMode,
      areaSqm: areaSqm ?? this.areaSqm,
      areaUnitPrice: areaUnitPrice ?? this.areaUnitPrice,
      contractAmount: contractAmount ?? this.contractAmount,
      settlementMonth: settlementMonth ?? this.settlementMonth,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'isAreaSite': isAreaSite,
    'areaAmountMode': areaAmountMode.key,
    'areaSqm': areaSqm,
    'areaUnitPrice': areaUnitPrice,
    'contractAmount': contractAmount,
    'settlementMonth': settlementMonth,
  };

  static Site fromJson(Map<String, dynamic> json) {
    return Site(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(_int(json['createdAt'])),
      isAreaSite: json['isAreaSite'] == true,
      areaAmountMode: AreaAmountMode.fromKey(json['areaAmountMode']),
      areaSqm: _double(json['areaSqm']),
      areaUnitPrice: _int(json['areaUnitPrice']),
      contractAmount: _int(json['contractAmount']),
      settlementMonth: (json['settlementMonth'] as String?) ?? '',
    );
  }
}

/// One entry of a worker on one day (出面). Since 1.0.6 a worker can have
/// several entries on the same day (another 現場, 昼 and 夜勤), so every entry
/// has its own [id].
///
/// The pay type and rates are copied in when the record is made, so a later
/// raise does not rewrite months that were already paid.
class DayRecord {
  DayRecord({
    String? id,
    this.shift = Shift.day,
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
    this.allowance = 0,
    this.allowanceMemo = '',
    this.transport = 0,
    this.parking = 0,
  }) : id = id ?? createId();

  /// Unique per entry. Files before 1.0.6 get `workerId@day`.
  final String id;

  /// 昼 or 夜勤.
  final Shift shift;

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

  /// 人工: 1.0 for a full day, 0.5 for a half day, more for a 外注 crew
  /// (0.5 steps, up to [maxUnitsPerRecord]).
  final double units;
  final double overtimeHours;
  final int dayRate;
  final int overtimeRate;

  /// 色付け: an optional extra yen for a tough day. Not part of 日当.
  /// Files before 1.0.7 have none.
  final int allowance;

  /// Optional memo for [allowance].
  final String allowanceMemo;

  /// 交通費: optional travel expense in yen. Not part of 日当.
  /// Files before this field have none.
  final int transport;

  /// 駐車場代: optional parking expense in yen. Not part of 日当.
  final int parking;

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

  DayRecord withId(String newId) => DayRecord(
    id: newId,
    shift: shift,
    workerId: workerId,
    day: day,
    siteId: siteId,
    units: units,
    overtimeHours: overtimeHours,
    dayRate: dayRate,
    overtimeRate: overtimeRate,
    payType: payType,
    hours: hours,
    hourlyRate: hourlyRate,
    monthlySalary: monthlySalary,
    allowance: allowance,
    allowanceMemo: allowanceMemo,
    transport: transport,
    parking: parking,
  );

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
    Shift? shift,
    int? allowance,
    String? allowanceMemo,
    int? transport,
    int? parking,
  }) {
    return DayRecord(
      id: id,
      shift: shift ?? this.shift,
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
      allowance: allowance ?? this.allowance,
      allowanceMemo: allowanceMemo ?? this.allowanceMemo,
      transport: transport ?? this.transport,
      parking: parking ?? this.parking,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'shift': shift.key,
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
    'allowance': allowance,
    'allowanceMemo': allowanceMemo,
    'transport': transport,
    'parking': parking,
  };

  static DayRecord fromJson(Map<String, dynamic> json) {
    final workerId = json['workerId'] as String;
    final day = json['day'] as String;
    final id = json['id'];
    return DayRecord(
      id: id is String && id.isNotEmpty ? id : '$workerId@$day',
      shift: Shift.fromKey(json['shift']),
      workerId: workerId,
      day: day,
      siteId: (json['siteId'] as String?) ?? '',
      payType: PayType.fromKey(json['payType']),
      units: _double(json['units'], fallback: 1),
      hours: _double(json['hours']),
      overtimeHours: _double(json['overtimeHours']),
      dayRate: _int(json['dayRate']),
      hourlyRate: _int(json['hourlyRate']),
      monthlySalary: _int(json['monthlySalary']),
      overtimeRate: _int(json['overtimeRate']),
      allowance: _int(json['allowance']),
      allowanceMemo: (json['allowanceMemo'] as String?) ?? '',
      transport: _int(json['transport']),
      parking: _int(json['parking']),
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
