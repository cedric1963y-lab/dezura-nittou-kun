import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime(2026, 9, 1);
  final yamada = Worker(
    id: 'w1',
    name: '山田 太郎',
    dayRate: 18000,
    overtimeRate: 2500,
    createdAt: created,
  );
  final sato = Worker(
    id: 'w2',
    name: '佐藤 健',
    dayRate: 15000,
    overtimeRate: 0,
    createdAt: created,
  );
  final kohoku = Site(id: 's1', name: '港北倉庫改修', note: '', createdAt: created);
  final minami = Site(id: 's2', name: '南区マンション', note: '', createdAt: created);

  DayRecord rec(
    Worker w,
    String day,
    Site s, {
    double units = 1,
    double ot = 0,
  }) {
    return DayRecord(
      workerId: w.id,
      day: day,
      siteId: s.id,
      units: units,
      overtimeHours: ot,
      dayRate: w.dayRate,
      overtimeRate: w.overtimeRate,
    );
  }

  final records = [
    rec(yamada, '2026-10-01', kohoku),
    rec(yamada, '2026-10-02', kohoku, ot: 2),
    rec(yamada, '2026-10-03', minami, units: 0.5),
    rec(sato, '2026-10-01', kohoku),
    rec(sato, '2026-10-02', minami, units: 0.5),
    rec(sato, '2026-09-30', kohoku),
    DayRecord(
      workerId: 'deleted',
      day: '2026-10-01',
      siteId: 's1',
      units: 1,
      overtimeHours: 0,
      dayRate: 99999,
      overtimeRate: 0,
    ),
  ];

  final summary = summarizeMonth(
    month: DateTime(2026, 10),
    workers: [yamada, sato],
    sites: [kohoku, minami],
    records: records,
  );

  test('totals per worker include half days and overtime', () {
    expect(summary.workers.length, 2);
    final y = summary.workers.first;
    expect(y.worker.id, 'w1');
    expect(y.days, 3);
    expect(y.units, 2.5);
    expect(y.overtimeHours, 2);
    expect(y.amount, 18000 + 18000 + 5000 + 9000);
    expect(y.unitsByDay, {1: 1.0, 2: 1.0, 3: 0.5});
    final s = summary.workers.last;
    expect(s.units, 1.5);
    expect(s.amount, 15000 + 7500);
  });

  test('other months and deleted workers are left out', () {
    expect(summary.records.length, 5);
    expect(summary.units, 4);
    expect(summary.amount, 50000 + 22500);
    expect(summary.workingDays, 3);
  });

  test('totals per site, most 人工 first', () {
    expect(summary.sites.map((s) => s.site.id), ['s1', 's2']);
    expect(summary.sites.first.units, 3);
    expect(summary.sites.first.workerCount, 2);
    expect(summary.sites.first.amount, 18000 + 23000 + 15000);
    expect(summary.sites.last.units, 1);
  });

  test('LINE text lists workers, sites and the total', () {
    final text = summaryAsText(summary);
    expect(text, startsWith('【出面・日当】2026年10月'));
    expect(text, contains('山田 太郎　2.5人工（3日） 残業2h　¥50,000'));
    expect(text, contains('港北倉庫改修　3人工　¥56,000'));
    expect(text, contains('合計　4人工　¥72,500'));
  });

  test('CSV has a BOM, one row per record and a total row', () {
    final csv = summaryAsCsv(summary);
    expect(csv.startsWith('\uFEFF日付,職人,現場,人工,残業時間,日当,残業単価,金額'), isTrue);
    final lines = csv.trim().split('\n');
    expect(lines.length, 1 + 5 + 1);
    expect(lines[1], '2026-10-01,山田 太郎,港北倉庫改修,1,0,18000,2500,18000');
    expect(lines.last, '合計,,,4,2,,,72500');
  });

  test('empty month', () {
    final empty = summarizeMonth(
      month: DateTime(2026, 8),
      workers: [yamada],
      sites: [kohoku],
      records: records,
    );
    expect(empty.isEmpty, isTrue);
    expect(summaryAsText(empty), contains('まだありません'));
  });
}
