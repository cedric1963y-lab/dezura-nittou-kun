import '../format.dart';
import '../models/records.dart';

class WorkerTotal {
  const WorkerTotal({
    required this.worker,
    required this.days,
    required this.units,
    required this.overtimeHours,
    required this.amount,
    required this.unitsByDay,
    this.nightDays = const {},
    this.breakdown = const [],
    this.payType = PayType.daily,
    this.hours = 0,
    this.salary = 0,
    this.wageAmount = 0,
    this.allowance = 0,
    this.areaAmount = 0,
  });

  final Worker worker;

  WorkerKind get kind => worker.kind;

  /// `日当` / `時給` / `月給`, or `単価` for a 外注 paid per 人工.
  String get payName =>
      kind == WorkerKind.contractor && payType == PayType.daily
      ? '単価'
      : payType.label;

  /// Days of month that include a 夜勤 entry, for the PDF grid.
  final Set<int> nightDays;

  /// Units and amount per 現場 and 昼/夜勤 (only the combinations used).
  final List<BreakdownRow> breakdown;

  /// Pay type of this worker's records in the month (the latest one if it
  /// was changed during the month).
  final PayType payType;

  /// Working hours of hourly records.
  final double hours;

  /// 月給 counted once for the month. Already included in [amount].
  final int salary;

  /// 日当・時給・残業 in this month (0 on 平米 sites). Already in [amount].
  final int wageAmount;

  /// 色付け in this month. Already in [amount].
  final int allowance;

  /// This worker's share of 平米/請負 amounts settling this month.
  /// Already in [amount].
  final int areaAmount;

  /// Days with any record (a half day counts as one day here).
  final int days;
  final double units;
  final double overtimeHours;
  final int amount;

  /// Day of month -> 人工 (all entries of that day added), for the PDF grid.
  final Map<int, double> unitsByDay;
}

/// One worker at one 現場 in one shift, summed over the month.
class BreakdownRow {
  const BreakdownRow({
    required this.worker,
    required this.site,
    required this.shift,
    required this.units,
    required this.amount,
    required this.days,
    this.wageAmount = 0,
    this.allowance = 0,
  });

  final Worker worker;
  final Site site;
  final Shift shift;
  final double units;

  /// Without 月給 (counted once per month on the worker) and without
  /// 平米割り (counted once per site in the 集計月).
  final int amount;
  final int wageAmount;
  final int allowance;
  final int days;
}

class SiteTotal {
  const SiteTotal({
    required this.site,
    required this.units,
    required this.amount,
    required this.workerCount,
    this.nightUnits = 0,
    this.wageAmount = 0,
    this.allowance = 0,
    this.areaAmount = 0,
    this.allUnits = 0,
  });

  /// 人工 of 夜勤 entries, included in [units].
  final double nightUnits;
  double get dayUnits => units - nightUnits;

  final Site site;

  /// 人工 in this month only.
  final double units;

  /// 人工 across every month of the job. Used for a 平米 split.
  final double allUnits;
  final int amount;
  final int wageAmount;
  final int allowance;

  /// Lump 平米/請負 amount counted in this month (0 otherwise).
  final int areaAmount;
  final int workerCount;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.workers,
    required this.sites,
    required this.records,
  });

  final DateTime month;
  final List<WorkerTotal> workers;
  final List<SiteTotal> sites;

  /// Records in this month, sorted by day then worker order.
  final List<DayRecord> records;

  List<WorkerTotal> workersOf(WorkerKind kind) => [
    for (final w in workers)
      if (w.kind == kind) w,
  ];

  /// True when any 外注 has an entry this month. Then the summary shows
  /// 従業員 and 外注 subtotals.
  bool get hasContractor => workers.any((w) => w.kind == WorkerKind.contractor);

  double unitsOf(WorkerKind kind) =>
      workersOf(kind).fold(0, (sum, w) => sum + w.units);
  int amountOf(WorkerKind kind) =>
      workersOf(kind).fold(0, (sum, w) => sum + w.amount);
  int daysOf(WorkerKind kind) => records
      .where((r) => workersOf(kind).any((w) => w.worker.id == r.workerId))
      .map((r) => r.day)
      .toSet()
      .length;

  double get nightUnits => sites.fold(0, (sum, s) => sum + s.nightUnits);

  double get units => workers.fold(0, (sum, w) => sum + w.units);
  double get overtimeHours =>
      workers.fold(0, (sum, w) => sum + w.overtimeHours);
  int get amount => workers.fold(0, (sum, w) => sum + w.amount);

  /// 月給 in [amount]. Site totals do not include it.
  int get salaryTotal => workers.fold(0, (sum, w) => sum + w.salary);
  int get allowanceTotal => workers.fold(0, (sum, w) => sum + w.allowance);
  int get areaTotal => workers.fold(0, (sum, w) => sum + w.areaAmount);
  int get wageTotal => workers.fold(0, (sum, w) => sum + w.wageAmount);
  bool get hasMonthly => workers.any((w) => w.payType == PayType.monthly);
  bool get hasAllowance => allowanceTotal > 0;
  bool get hasArea => areaTotal > 0 || sites.any((s) => s.areaAmount > 0);
  int get workingDays => records.map((r) => r.day).toSet().length;
  bool get isEmpty => records.isEmpty && workers.isEmpty;
}

/// 日当・時給・残業 for one entry. Always 0 on a 平米 site (the lump
/// sum is split separately, so nothing is counted twice).
int wageOf(DayRecord record, Site site) => site.isAreaSite ? 0 : record.amount;

/// Split [total] yen in proportion to [weights] (人工). The shares sum
/// exactly to [total] (largest-remainder method).
List<int> splitByUnits(int total, List<double> weights) {
  if (weights.isEmpty) return const [];
  final sumW = weights.fold<double>(0, (a, b) => a + b);
  if (total <= 0 || sumW <= 0) {
    return List<int>.filled(weights.length, 0);
  }
  final raw = [for (final w in weights) total * w / sumW];
  final shares = [for (final x in raw) x.floor()];
  var left = total - shares.fold<int>(0, (a, b) => a + b);
  final order = [for (var i = 0; i < raw.length; i++) i]
    ..sort((a, b) {
      final byFrac = (raw[b] - shares[b]).compareTo(raw[a] - shares[a]);
      return byFrac != 0 ? byFrac : a.compareTo(b);
    });
  for (var i = 0; i < left; i++) {
    shares[order[i]]++;
  }
  return shares;
}

/// Totals per worker and per site for [month]. Workers and sites with no
/// record that month are left out, except a 平米 site whose 集計月 is this
/// month: its lump sum is split by 人工 over the whole job and counted
/// here, even if some (or all) of the work was in another month.
/// Records whose worker or site was deleted are skipped.
MonthSummary summarizeMonth({
  required DateTime month,
  required List<Worker> workers,
  required List<Site> sites,
  required List<DayRecord> records,
}) {
  final prefix = '${monthKey(month)}-';
  final monthKeyValue = monthKey(month);
  final workerOrder = {
    for (var i = 0; i < workers.length; i++) workers[i].id: i,
  };
  final siteById = {for (final s in sites) s.id: s};
  bool usable(DayRecord r) =>
      tryParseDayKey(r.day) != null &&
      workerOrder.containsKey(r.workerId) &&
      siteById.containsKey(r.siteId);

  final inMonth =
      [
        for (final r in records)
          if (r.day.startsWith(prefix) && usable(r)) r,
      ]..sort((a, b) {
        final byDay = a.day.compareTo(b.day);
        if (byDay != 0) return byDay;
        final byWorker = workerOrder[a.workerId]!.compareTo(
          workerOrder[b.workerId]!,
        );
        if (byWorker != 0) return byWorker;
        return a.shift.index.compareTo(b.shift.index);
      });

  // 平米/請負: one 集計月 per site, split by all 人工 on that site.
  final areaByWorker = <String, int>{};
  final areaSiteUnits = <String, double>{};
  final areaSiteAmount = <String, int>{};
  final areaSiteWorkers = <String, Set<String>>{};
  for (final site in sites) {
    if (!site.isAreaSite || site.settlementMonth != monthKeyValue) continue;
    final here = [
      for (final r in records)
        if (r.siteId == site.id && usable(r)) r,
    ];
    final unitsByWorker = <String, double>{};
    for (final r in here) {
      unitsByWorker[r.workerId] = (unitsByWorker[r.workerId] ?? 0) + r.units;
    }
    final ids = unitsByWorker.keys.toList()
      ..sort((a, b) => workerOrder[a]!.compareTo(workerOrder[b]!));
    final weights = [for (final id in ids) unitsByWorker[id]!];
    final allUnits = weights.fold<double>(0, (a, b) => a + b);
    final shares = splitByUnits(site.areaTotal, weights);
    areaSiteUnits[site.id] = allUnits;
    areaSiteAmount[site.id] = site.areaTotal;
    areaSiteWorkers[site.id] = ids.toSet();
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      areaByWorker[id] = (areaByWorker[id] ?? 0) + shares[i];
    }
  }

  final workerIds = <String>{
    for (final r in inMonth) r.workerId,
    ...areaByWorker.keys,
  };

  final workerTotals = <WorkerTotal>[];
  for (final worker in workers) {
    if (!workerIds.contains(worker.id)) continue;
    final mine = inMonth.where((r) => r.workerId == worker.id).toList();
    final monthly = mine.where((r) => r.payType == PayType.monthly);
    // Once per month, whatever the attendance. No proration.
    final salary = monthly.isEmpty ? 0 : monthly.last.monthlySalary;
    final unitsByDay = <int, double>{};
    for (final r in mine) {
      if (tryParseDayKey(r.day) case final date?) {
        unitsByDay[date.day] = (unitsByDay[date.day] ?? 0) + r.units;
      }
    }
    final breakdown = <BreakdownRow>[];
    for (final site in sites) {
      for (final shift in Shift.values) {
        final part = mine
            .where((r) => r.siteId == site.id && r.shift == shift)
            .toList();
        if (part.isEmpty) continue;
        final wage = part.fold(0, (sum, r) => sum + wageOf(r, site));
        final allowance = part.fold(0, (sum, r) => sum + r.allowance);
        breakdown.add(
          BreakdownRow(
            worker: worker,
            site: site,
            shift: shift,
            units: part.fold(0, (sum, r) => sum + r.units),
            wageAmount: wage,
            allowance: allowance,
            amount: wage + allowance,
            days: part.map((r) => r.day).toSet().length,
          ),
        );
      }
    }
    var wage = 0;
    var allowance = 0;
    for (final r in mine) {
      wage += wageOf(r, siteById[r.siteId]!);
      allowance += r.allowance;
    }
    final areaAmount = areaByWorker[worker.id] ?? 0;
    final payType = mine.isNotEmpty ? mine.last.payType : worker.payType;
    workerTotals.add(
      WorkerTotal(
        worker: worker,
        payType: payType,
        hours: mine
            .where((r) => r.payType == PayType.hourly)
            .fold(0, (sum, r) => sum + r.hours),
        salary: salary,
        wageAmount: wage,
        allowance: allowance,
        areaAmount: areaAmount,
        days: mine.map((r) => r.day).toSet().length,
        units: mine.fold(0, (sum, r) => sum + r.units),
        overtimeHours: mine.fold(0, (sum, r) => sum + r.overtimeHours),
        amount: wage + allowance + areaAmount + salary,
        unitsByDay: unitsByDay,
        nightDays: {
          for (final r in mine)
            if (r.shift == Shift.night)
              if (tryParseDayKey(r.day) case final date?) date.day,
        },
        breakdown: breakdown,
      ),
    );
  }

  final siteTotals = <SiteTotal>[];
  for (final site in sites) {
    final here = inMonth.where((r) => r.siteId == site.id).toList();
    final areaAmount = areaSiteAmount[site.id] ?? 0;
    if (here.isEmpty && areaAmount == 0) continue;
    final wage = here.fold(0, (sum, r) => sum + wageOf(r, site));
    final allowance = here.fold(0, (sum, r) => sum + r.allowance);
    final workerCount = {
      ...here.map((r) => r.workerId),
      ...?areaSiteWorkers[site.id],
    }.length;
    siteTotals.add(
      SiteTotal(
        site: site,
        units: here.fold(0, (sum, r) => sum + r.units),
        allUnits: areaSiteUnits[site.id] ??
            here.fold(0, (sum, r) => sum + r.units),
        wageAmount: wage,
        allowance: allowance,
        areaAmount: areaAmount,
        amount: wage + allowance + areaAmount,
        workerCount: workerCount,
        nightUnits: here
            .where((r) => r.shift == Shift.night)
            .fold(0, (sum, r) => sum + r.units),
      ),
    );
  }
  siteTotals.sort((a, b) => b.units.compareTo(a.units));

  return MonthSummary(
    month: firstOfMonth(month),
    workers: workerTotals,
    sites: siteTotals,
    records: inMonth,
  );
}

/// Plain text that reads well in a LINE chat.
String summaryAsText(MonthSummary summary) {
  final b = StringBuffer()
    ..writeln('【出面・日当】${formatMonth(summary.month)}')
    ..writeln();
  if (summary.isEmpty) {
    b.writeln('この月の出面はまだありません。');
    return b.toString().trimRight();
  }
  void workerLines(Iterable<WorkerTotal> list) {
    for (final w in list) {
      final ot = w.overtimeHours > 0
          ? ' 残業${formatHours(w.overtimeHours)}'
          : '';
      b.writeln(
        // 日当 lines read exactly as before 1.0.5.
        '${w.worker.name}${w.payType == PayType.daily ? '' : '（${w.payType.label}）'}　${workerDetail(w)}$ot　${formatYen(w.amount)}',
      );
      // Only when the worker was split over several 現場 or 昼/夜勤.
      if (w.breakdown.length > 1) {
        for (final row in w.breakdown) {
          b.writeln('　└ ${breakdownLabel(row)}　${formatUnits(row.units)}人工');
        }
      }
      // 色付け and 平米割り are separate from 日当, and hidden when unused.
      if (w.allowance > 0 || w.areaAmount > 0) {
        if (w.wageAmount > 0 || w.salary > 0) {
          b.writeln('　└ 日当　${formatYen(w.wageAmount + w.salary)}');
        }
        if (w.allowance > 0) {
          b.writeln('　└ 色付け　${formatYen(w.allowance)}');
        }
        if (w.areaAmount > 0) {
          b.writeln('　└ 平米割り　${formatYen(w.areaAmount)}');
        }
      }
    }
  }

  if (summary.hasContractor) {
    for (final kind in WorkerKind.values) {
      final list = summary.workersOf(kind);
      if (list.isEmpty) continue;
      b.writeln('■ ${kind.label}');
      workerLines(list);
      b
        ..writeln(
          '${kind.label}小計　${formatUnits(summary.unitsOf(kind))}人工　${formatYen(summary.amountOf(kind))}',
        )
        ..writeln();
    }
  } else {
    b.writeln('■ 職人別');
    workerLines(summary.workers);
  }
  b
    ..writeln()
    ..writeln('■ 現場別');
  for (final s in summary.sites) {
    final night = s.nightUnits > 0
        ? '（昼${formatUnits(s.dayUnits)}・夜勤${formatUnits(s.nightUnits)}）'
        : '';
    b.writeln(
      '${s.site.name}　${formatUnits(s.units)}人工$night　${formatYen(s.amount)}',
    );
    if (s.allowance > 0 || s.areaAmount > 0) {
      if (s.wageAmount > 0) {
        b.writeln('　└ 日当　${formatYen(s.wageAmount)}');
      }
      if (s.allowance > 0) {
        b.writeln('　└ 色付け　${formatYen(s.allowance)}');
      }
      if (s.areaAmount > 0) {
        b.writeln('　└ 平米割り　${formatYen(s.areaAmount)}');
      }
    }
  }
  if (summary.hasMonthly) b.writeln(monthlySiteNote);
  if (summary.hasArea) b.writeln(areaSiteNote);
  b
    ..writeln('―――――――――')
    ..writeln(
      '合計　${formatUnits(summary.units)}人工　${formatYen(summary.amount)}',
    );
  if (summary.overtimeHours > 0) {
    b.writeln('（うち残業 ${formatHours(summary.overtimeHours)}）');
  }
  return b.toString().trimRight();
}

/// `現場A・昼` / `現場B・夜勤`.
String breakdownLabel(BreakdownRow row) =>
    '${row.site.name}・${row.shift.label}';

/// `3人工（3日）`, `24h（3日）` or `出勤3日（3人工）` by pay type.
String workerDetail(WorkerTotal w) => switch (w.payType) {
  PayType.daily => '${formatUnits(w.units)}人工（${w.days}日）',
  PayType.hourly => '${formatHours(w.hours)}（${w.days}日）',
  PayType.monthly => '出勤${w.days}日（${formatUnits(w.units)}人工）',
};

/// Shown under the per-site totals when a 月給 worker is in the month.
const monthlySiteNote = '※月給は現場別の金額に含みません（人工のみ数えます）';

/// Shown when a 平米 site settles in this month.
const areaSiteNote = '※平米の現場は、集計月に全期間の人工の割合で分けます（日当は付きません）';

/// UTF-8 CSV with one row per record. Starts with a BOM so Excel on Windows
/// opens the Japanese correctly.
String summaryAsCsv(MonthSummary summary) {
  final names = {for (final w in summary.workers) w.worker.id: w.worker.name};
  final kinds = {for (final w in summary.workers) w.worker.id: w.kind};
  final siteNames = {for (final s in summary.sites) s.site.id: s.site.name};
  final siteById = {for (final s in summary.sites) s.site.id: s.site};
  // The first 11 columns are the same as 1.0.5 (the first 8 as 1.0.4), so
  // existing sheets still work. 1.0.6 adds 昼夜 and 従業員/外注 at the end.
  // 色付け columns are appended only when this month has 色付け.
  final showAllowance = summary.hasAllowance;
  final b = StringBuffer('\uFEFF')
    ..writeln(
      [
        '日付,職人,現場,人工,残業時間,日当,残業単価,金額,区分,勤務時間,時給,昼夜,従業員外注',
        if (showAllowance) ',色付け,色付けメモ',
      ].join(),
    );
  String tail(int allowance, String memo) =>
      showAllowance ? ',${allowance > 0 ? allowance : ''},${_csv(memo)}' : '';

  for (final r in summary.records) {
    final site = siteById[r.siteId];
    final wage = site == null ? r.amount : wageOf(r, site);
    b.writeln(
      [
        r.day,
        _csv(names[r.workerId] ?? ''),
        _csv(siteNames[r.siteId] ?? ''),
        formatUnits(r.units),
        formatUnits(r.overtimeHours),
        r.payType == PayType.daily && (site == null || !site.isAreaSite)
            ? r.dayRate
            : '',
        site != null && site.isAreaSite ? '' : r.overtimeRate,
        wage,
        r.payType.label,
        r.payType == PayType.hourly ? formatUnits(r.hours) : '',
        r.payType == PayType.hourly ? r.hourlyRate : '',
        r.shift.label,
        (kinds[r.workerId] ?? WorkerKind.employee).label,
      ].join(',') +
          tail(r.allowance, r.allowanceMemo),
    );
  }
  for (final w in summary.workers) {
    if (w.salary == 0) continue;
    b.writeln(
      [
        monthKey(summary.month),
        _csv(w.worker.name),
        '',
        '',
        '',
        '',
        '',
        w.salary,
        '月給',
        '',
        '',
        '',
        w.kind.label,
      ].join(',') +
          tail(0, ''),
    );
  }
  for (final w in summary.workers) {
    if (w.areaAmount == 0) continue;
    // One row per worker for the month's 平米割り (all sites combined).
    b.writeln(
      [
        monthKey(summary.month),
        _csv(w.worker.name),
        '',
        '',
        '',
        '',
        '',
        w.areaAmount,
        '平米割り',
        '',
        '',
        '',
        w.kind.label,
      ].join(',') +
          tail(0, ''),
    );
  }
  if (summary.hasContractor) {
    for (final kind in WorkerKind.values) {
      b.writeln(
        '${kind.label}小計,,,${formatUnits(summary.unitsOf(kind))},${formatUnits(summary.workersOf(kind).fold(0.0, (sum, w) => sum + w.overtimeHours))},,,${summary.amountOf(kind)},,,,,${kind.label}${tail(0, '')}',
      );
    }
  }
  b.writeln(
    '合計,,,${formatUnits(summary.units)},${formatUnits(summary.overtimeHours)},,,${summary.amount},,,,,${tail(0, '')}',
  );
  return b.toString();
}

String _csv(String value) {
  if (value.contains(RegExp(r'[",\n\r]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
