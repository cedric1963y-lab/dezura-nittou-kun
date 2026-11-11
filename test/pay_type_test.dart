import 'dart:convert';
import 'dart:io';

import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/errors.dart';
import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:dezura_nittou/services/pdf_report.dart';
import 'package:dezura_nittou/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_pay_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    '1.0.4 files (version 1, no pay type) load as 日当 with no loss',
    () async {
      await directory.create(recursive: true);
      File(p.join(directory.path, 'workers.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'workers': [
            {
              'id': 'w1',
              'name': '山田 太郎',
              'dayRate': 18000,
              'overtimeRate': 2500,
              'createdAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
            },
          ],
        }),
      );
      File(p.join(directory.path, 'sites.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'sites': [
            {'id': 's1', 'name': '港北倉庫改修', 'note': '', 'createdAt': 0},
          ],
        }),
      );
      File(p.join(directory.path, 'records.json')).writeAsStringSync(
        jsonEncode({
          'version': 1,
          'records': [
            {
              'workerId': 'w1',
              'day': '2026-10-01',
              'siteId': 's1',
              'units': 1,
              'overtimeHours': 2,
              'dayRate': 18000,
              'overtimeRate': 2500,
            },
            {
              'workerId': 'w1',
              'day': '2026-10-02',
              'siteId': 's1',
              'units': 0.5,
              'overtimeHours': 0,
              'dayRate': 18000,
              'overtimeRate': 2500,
            },
          ],
        }),
      );

      final c = await openController(directory);
      final w = c.workers.single;
      expect(w.payType, PayType.daily);
      expect(w.dayRate, 18000);
      expect(w.overtimeRate, 2500);
      expect(c.records.every((r) => r.payType == PayType.daily), isTrue);
      final summary = c.summaryFor(DateTime(2026, 10));
      expect(summary.amount, 18000 + 5000 + 9000);
      expect(
        c.textFor(DateTime(2026, 10)),
        contains('山田 太郎　1.5人工（2日） 残業2h　¥32,000'),
      );

      // Saving writes version 2 and the same data reads back.
      await c.setBusinessName('山田工務店');
      await c.tapWorker(w.id, DateTime(2026, 10, 3));
      final saved = jsonDecode(
        File(p.join(directory.path, 'records.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['version'], Repository.listSchemaVersion);
      c.dispose();
      final again = await openController(directory);
      expect(again.records.length, 3);
      expect(again.summaryFor(DateTime(2026, 10)).amount, 32000 + 18000);
      again.dispose();
    },
  );

  test('unknown future file version is refused, not misread', () async {
    await directory.create(recursive: true);
    File(p.join(directory.path, 'workers.json'))
        .writeAsStringSync(jsonEncode({'version': 99, 'workers': []}));
    final repo = Repository(directory);
    await expectLater(repo.loadWorkers(), throwsA(isA<FormatException>()));
  });

  test('日当: 人工 x 日当 + 残業', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北倉庫改修');
    final w = await c.addWorker(
      name: '山田 太郎',
      dayRate: 18000,
      overtimeRate: 2500,
    );
    final day = DateTime(2026, 10, 1);
    await c.setRecord(
      workerId: w.id,
      day: day,
      siteId: c.sites.single.id,
      units: 0.5,
      overtimeHours: 1,
    );
    expect(c.recordFor(w.id, day)!.amount, 9000 + 2500);
    c.dispose();
  });

  test('時給: 8h default, half day 4h, editable hours, overtime', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北倉庫改修');
    final w = await c.addWorker(
      name: '山田 花子',
      payType: PayType.hourly,
      hourlyRate: 1500,
      overtimeRate: 1900,
    );
    final day = DateTime(2026, 10, 1);
    final first = await c.tapWorker(w.id, day);
    expect(first!.payType, PayType.hourly);
    expect(first.hours, 8);
    expect(first.amount, 12000);
    final half = await c.tapWorker(w.id, day);
    expect(half!.hours, 4);
    expect(half.amount, 6000);

    await c.setRecord(
      workerId: w.id,
      day: day,
      siteId: c.sites.single.id,
      units: 1,
      overtimeHours: 1.5,
      hours: 6.5,
    );
    final r = c.recordFor(w.id, day)!;
    expect(r.hours, 6.5);
    expect(r.amount, 9750 + 2850);
    await expectLater(
      c.setRecord(
        workerId: w.id,
        day: day,
        siteId: c.sites.single.id,
        units: 1,
        overtimeHours: 0,
        hours: 25,
      ),
      throwsA(isA<InvalidInput>()),
    );
    c.dispose();
  });

  test(
    '月給: salary once per month, attendance counted, sites exclude it',
    () async {
      final c = await openController(directory, premium: true);
      await c.addSite(name: '港北倉庫改修');
      await c.addSite(name: '南区マンション');
      final taro = await c.addWorker(name: '山田 太郎', dayRate: 18000);
      final hanako = await c.addWorker(
        name: '山田 花子',
        payType: PayType.monthly,
        monthlySalary: 300000,
        overtimeRate: 2000,
      );
      final kohoku = c.sites.first.id;
      final minami = c.sites.last.id;
      for (var d = 1; d <= 3; d++) {
        await c.setRecord(
          workerId: hanako.id,
          day: DateTime(2026, 10, d),
          siteId: d == 3 ? minami : kohoku,
          units: d == 2 ? 0.5 : 1,
          overtimeHours: d == 1 ? 1 : 0,
        );
      }
      await c.setRecord(
        workerId: taro.id,
        day: DateTime(2026, 10, 1),
        siteId: kohoku,
        units: 1,
        overtimeHours: 0,
      );

      final s = c.summaryFor(DateTime(2026, 10));
      final h = s.workers.firstWhere((w) => w.worker.id == hanako.id);
      expect(h.payType, PayType.monthly);
      expect(h.days, 3);
      expect(h.units, 2.5);
      expect(h.salary, 300000);
      expect(h.amount, 300000 + 2000);
      expect(s.amount, 300000 + 2000 + 18000);
      expect(s.salaryTotal, 300000);
      expect(s.hasMonthly, isTrue);
      final k = s.sites.firstWhere((x) => x.site.id == kohoku);
      expect(k.units, 2.5);
      expect(k.amount, 2000 + 18000);
      final m = s.sites.firstWhere((x) => x.site.id == minami);
      expect(m.amount, 0);

      final text = summaryAsText(s);
      expect(text, contains('山田 花子（月給）　出勤3日（2.5人工） 残業1h　¥302,000'));
      expect(text, contains('山田 太郎　1人工（1日）　¥18,000'));
      expect(text, contains(monthlySiteNote));
      expect(text, contains('合計　3.5人工　¥320,000'));

      final csv = summaryAsCsv(s).trim().split('\n');
      expect(csv, contains('2026-10,山田 花子,,,,,,300000,月給,,'));
      expect(csv.last, '合計,,,3.5,1,,,320000,,,');

      // Nothing for a month without attendance.
      expect(c.summaryFor(DateTime(2026, 11)).amount, 0);

      final pdf = await c.exportPdf(DateTime(2026, 10));
      expect(File(pdf).readAsBytesSync().take(4), '%PDF'.codeUnits);
      c.dispose();
    },
  );

  test('changing to 時給 mid-month rewrites this month only', () async {
    final c = await openController(directory, premium: true);
    await c.addSite(name: '港北倉庫改修');
    final w = await c.addWorker(name: '山田 太郎', dayRate: 18000);
    await c.tapWorker(w.id, DateTime(2026, 9, 30));
    await c.tapWorker(w.id, DateTime(2026, 10, 1));
    await c.tapWorker(w.id, DateTime(2026, 10, 2));
    await c.tapWorker(w.id, DateTime(2026, 10, 2)); // half day
    await c.updateWorker(
      id: w.id,
      name: '山田 太郎',
      payType: PayType.hourly,
      hourlyRate: 2000,
    );
    expect(c.recordFor(w.id, DateTime(2026, 9, 30))!.amount, 18000);
    expect(c.recordFor(w.id, DateTime(2026, 10, 1))!.amount, 16000);
    expect(c.recordFor(w.id, DateTime(2026, 10, 2))!.amount, 8000);
    final t = c.summaryFor(DateTime(2026, 10)).workers.single;
    expect(t.payType, PayType.hourly);
    expect(t.hours, 12);
    expect(workerDetail(t), '12h（2日）');
    c.dispose();
  });

  test('PDF builds for every pay type mixed', () async {
    final created = DateTime(2026, 9, 1);
    Worker worker(String id, String name, PayType type) => Worker(
      id: id,
      name: name,
      payType: type,
      dayRate: 18000,
      hourlyRate: 1500,
      monthlySalary: 280000,
      overtimeRate: 2000,
      createdAt: created,
    );
    final workers = [
      worker('w1', '山田 太郎', PayType.daily),
      worker('w2', '山田 花子', PayType.hourly),
      worker('w3', '山田 一郎', PayType.monthly),
    ];
    final site = Site(id: 's1', name: '港北倉庫改修', note: '', createdAt: created);
    final records = [
      for (final w in workers)
        for (var d = 1; d <= 5; d++)
          DayRecord(
            workerId: w.id,
            day: '2026-10-0$d',
            siteId: 's1',
            units: 1,
            overtimeHours: 0,
            payType: w.payType,
            hours: w.payType == PayType.hourly ? 8 : 0,
            dayRate: w.dayRate,
            hourlyRate: w.hourlyRate,
            monthlySalary: w.monthlySalary,
            overtimeRate: w.overtimeRate,
          ),
    ];
    final summary = summarizeMonth(
      month: DateTime(2026, 10),
      workers: workers,
      sites: [site],
      records: records,
    );
    expect(summary.amount, 90000 + 60000 + 280000);
    expect(summary.sites.single.amount, 90000 + 60000);
    final bytes = await buildMonthlyPdf(
      fontData: await loadTestFont(),
      summary: summary,
      title: '山田工務店',
    );
    expect(bytes.take(4), '%PDF'.codeUnits);
  });

  testWidgets('worker dialog picks 時給 and returns the hourly rate', (
    tester,
  ) async {
    WorkerDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => draft = await showWorkerDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('worker-name')), '山田 花子');
    await tester.tap(find.byKey(const Key('pay-hourly')));
    await tester.pumpAndSettle();
    expect(find.text('時給（1時間あたり）'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('worker-rate-hourly')), '1500');
    await tester.tap(find.byKey(const Key('save-worker')));
    await tester.pumpAndSettle();
    expect(draft!.payType, PayType.hourly);
    expect(draft!.hourlyRate, 1500);
    expect(draft!.name, '山田 花子');
  });
}
