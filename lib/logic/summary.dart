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
  });

  final Worker worker;

  /// Days with any record (a half day counts as one day here).
  final int days;
  final double units;
  final double overtimeHours;
  final int amount;

  /// Day of month -> 人工, for the PDF grid.
  final Map<int, double> unitsByDay;
}

class SiteTotal {
  const SiteTotal({
    required this.site,
    required this.units,
    required this.amount,
    required this.workerCount,
  });

  final Site site;
  final double units;
  final int amount;
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

  double get units => workers.fold(0, (sum, w) => sum + w.units);
  double get overtimeHours => workers.fold(0, (sum, w) => sum + w.overtimeHours);
  int get amount => workers.fold(0, (sum, w) => sum + w.amount);
  int get workingDays => records.map((r) => r.day).toSet().length;
  bool get isEmpty => records.isEmpty;
}

/// Totals per worker and per site for [month]. Workers and sites with no
/// record that month are left out. Records whose worker or site was deleted
/// are skipped.
MonthSummary summarizeMonth({
  required DateTime month,
  required List<Worker> workers,
  required List<Site> sites,
  required List<DayRecord> records,
}) {
  final prefix = '${monthKey(month)}-';
  final workerOrder = {
    for (var i = 0; i < workers.length; i++) workers[i].id: i,
  };
  final siteById = {for (final s in sites) s.id: s};
  final inMonth = [
    for (final r in records)
      if (r.day.startsWith(prefix) &&
          workerOrder.containsKey(r.workerId) &&
          siteById.containsKey(r.siteId))
        r,
  ]..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      return workerOrder[a.workerId]!.compareTo(workerOrder[b.workerId]!);
    });

  final workerTotals = <WorkerTotal>[];
  for (final worker in workers) {
    final mine = inMonth.where((r) => r.workerId == worker.id).toList();
    if (mine.isEmpty) continue;
    workerTotals.add(
      WorkerTotal(
        worker: worker,
        days: mine.map((r) => r.day).toSet().length,
        units: mine.fold(0, (sum, r) => sum + r.units),
        overtimeHours: mine.fold(0, (sum, r) => sum + r.overtimeHours),
        amount: mine.fold(0, (sum, r) => sum + r.amount),
        unitsByDay: {
          for (final r in mine) parseDayKey(r.day).day: r.units,
        },
      ),
    );
  }

  final siteTotals = <SiteTotal>[];
  for (final site in sites) {
    final here = inMonth.where((r) => r.siteId == site.id).toList();
    if (here.isEmpty) continue;
    siteTotals.add(
      SiteTotal(
        site: site,
        units: here.fold(0, (sum, r) => sum + r.units),
        amount: here.fold(0, (sum, r) => sum + r.amount),
        workerCount: here.map((r) => r.workerId).toSet().length,
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
  b.writeln('■ 職人別');
  for (final w in summary.workers) {
    final ot = w.overtimeHours > 0 ? ' 残業${formatHours(w.overtimeHours)}' : '';
    b.writeln(
      '${w.worker.name}　${formatUnits(w.units)}人工（${w.days}日）$ot　${formatYen(w.amount)}',
    );
  }
  b
    ..writeln()
    ..writeln('■ 現場別');
  for (final s in summary.sites) {
    b.writeln('${s.site.name}　${formatUnits(s.units)}人工　${formatYen(s.amount)}');
  }
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

/// UTF-8 CSV with one row per record. Starts with a BOM so Excel on Windows
/// opens the Japanese correctly.
String summaryAsCsv(MonthSummary summary) {
  final names = {for (final w in summary.workers) w.worker.id: w.worker.name};
  final siteNames = {for (final s in summary.sites) s.site.id: s.site.name};
  final b = StringBuffer('\uFEFF')
    ..writeln('日付,職人,現場,人工,残業時間,日当,残業単価,金額');
  for (final r in summary.records) {
    b.writeln(
      [
        r.day,
        _csv(names[r.workerId] ?? ''),
        _csv(siteNames[r.siteId] ?? ''),
        formatUnits(r.units),
        formatUnits(r.overtimeHours),
        r.dayRate,
        r.overtimeRate,
        r.amount,
      ].join(','),
    );
  }
  b.writeln(
    '合計,,,${formatUnits(summary.units)},${formatUnits(summary.overtimeHours)},,,${summary.amount}',
  );
  return b.toString();
}

String _csv(String value) {
  if (value.contains(RegExp(r'[",\n\r]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
