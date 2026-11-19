import 'dart:convert';
import 'dart:io';

import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/errors.dart';
import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:dezura_nittou/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_106_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  void write(String name, Map<String, dynamic> json) {
    directory.createSync(recursive: true);
    File(p.join(directory.path, name)).writeAsStringSync(jsonEncode(json));
  }

  group('migration', () {
    for (final version in [1, 2]) {
      test(
        'version $version files load unchanged as 従業員 / 昼 with ids',
        () async {
          write('workers.json', {
            'version': version,
            'workers': [
              {
                'id': 'w1',
                'name': '山田 太郎',
                'dayRate': 18000,
                'overtimeRate': 2500,
                'createdAt': 0,
              },
            ],
          });
          write('sites.json', {
            'version': version,
            'sites': [
              {'id': 's1', 'name': '港北', 'note': '', 'createdAt': 0},
            ],
          });
          write('records.json', {
            'version': version,
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
          });
          final c = await openController(directory, premium: true);
          expect(c.workers.single.kind, WorkerKind.employee);
          expect(c.records.length, 2);
          expect(c.records.map((r) => r.shift), everyElement(Shift.day));
          expect(c.records.map((r) => r.id).toSet().length, 2);
          expect(c.records.first.id, 'w1@2026-10-01');
          final s = c.summaryFor(DateTime(2026, 10));
          expect(s.units, 1.5);
          expect(s.amount, 18000 + 5000 + 9000);
          expect(s.hasContractor, isFalse);

          // Saving rewrites in v3 and reloading keeps the same data.
          await c.tapWorker('w1', DateTime(2026, 10, 3));
          final saved = jsonDecode(
            File(p.join(directory.path, 'records.json')).readAsStringSync(),
          );
          expect(saved['version'], Repository.listSchemaVersion);
          c.dispose();
          final again = await openController(directory, premium: true);
          expect(again.records.length, 3);
          expect(again.records.first.id, 'w1@2026-10-01');
          again.dispose();
        },
      );
    }

    test(
      'repeated ids in a damaged file are kept as separate entries',
      () async {
        write('records.json', {
          'version': 3,
          'records': [
            for (final site in ['s1', 's2'])
              {
                'id': 'same',
                'workerId': 'w1',
                'day': '2026-10-01',
                'siteId': site,
                'units': 0.5,
              },
          ],
        });
        final repo = Repository(directory);
        final records = await repo.loadRecords();
        expect(records.length, 2);
        expect(records.map((r) => r.id).toSet().length, 2);
      },
    );

    test('unknown future version is rejected', () async {
      write('records.json', {'version': 6, 'records': []});
      await expectLater(
        Repository(directory).loadRecords(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('same day, several entries', () {
    test('split 半日 across two 現場 and 昼 + 夜勤', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: '現場A');
      final b = await c.addSite(name: '現場B');
      final w = await c.addWorker(
        name: '山田',
        dayRate: 18000,
        overtimeRate: 2500,
      );
      final day = DateTime(2026, 10, 5);
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: a.id,
        units: 0.5,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: b.id,
        units: 0.5,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 6),
        siteId: a.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 6),
        siteId: a.id,
        units: 1,
        overtimeHours: 1,
        shift: Shift.night,
      );
      expect(c.recordsFor(w.id, day).length, 2);
      expect(c.recordsFor(w.id, DateTime(2026, 10, 6)).length, 2);

      final s = c.summaryFor(DateTime(2026, 10));
      final t = s.workers.single;
      expect(t.units, 3);
      expect(t.days, 2);
      expect(t.amount, 9000 + 9000 + 18000 + 18000 + 2500);
      expect(t.unitsByDay, {5: 1.0, 6: 2.0});
      expect(t.nightDays, {6});
      expect(t.breakdown.length, 3);
      final siteA = s.sites.firstWhere((x) => x.site.id == a.id);
      expect(siteA.units, 2.5);
      expect(siteA.nightUnits, 1);
      expect(siteA.dayUnits, 1.5);
      expect(s.workingDays, 2);
      expect(c.unitsByDay(DateTime(2026, 10)), {5: 1.0, 6: 2.0});

      final text = summaryAsText(s);
      expect(text, contains('└ 現場A・昼　1.5人工'));
      expect(text, contains('└ 現場A・夜勤　1人工'));
      expect(text, contains('現場A　2.5人工（昼1.5・夜勤1）'));
      final csv = summaryAsCsv(s);
      expect(
        csv,
        contains('2026-10-06,山田,現場A,1,1,18000,2500,20500,日当,,,夜勤,従業員'),
      );

      // Edit one entry, remove another, others stay.
      final first = c.recordsFor(w.id, day).first;
      await c.clearRecordById(first.id);
      expect(c.recordsFor(w.id, day).length, 1);
      c.dispose();
    });

    test('same worker, day, 現場 and shift cannot be entered twice', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: 'A');
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      final day = DateTime(2026, 10, 5);
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: a.id,
        units: 0.5,
        overtimeHours: 0,
      );
      await expectLater(
        c.setRecord(
          workerId: w.id,
          day: day,
          siteId: a.id,
          units: 0.5,
          overtimeHours: 0,
        ),
        throwsA(isA<InvalidInput>()),
      );
      expect(c.recordsFor(w.id, day).length, 1);
      c.dispose();
    });

    test('tap cycles the first entry and keeps the others', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: 'A');
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      final day = DateTime(2026, 10, 5);
      await c.tapWorker(w.id, day);
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: a.id,
        units: 1,
        overtimeHours: 0,
        shift: Shift.night,
      );
      await c.tapWorker(w.id, day); // first: 1 -> 0.5
      expect(c.recordsFor(w.id, day).map((r) => r.units), [0.5, 1]);
      await c.tapWorker(w.id, day); // first removed
      expect(c.recordsFor(w.id, day).map((r) => r.shift), [Shift.night]);
      c.dispose();
    });

    test('markAll skips 外注 and workers who already have an entry', () async {
      final c = await openController(directory, premium: true);
      await c.addSite(name: 'A');
      await c.addWorker(name: '山田', dayRate: 18000);
      await c.addWorker(
        name: '山田工業',
        kind: WorkerKind.contractor,
        dayRate: 25000,
      );
      expect(await c.markAll(DateTime(2026, 10, 5)), 1);
      expect(await c.markAll(DateTime(2026, 10, 5)), 0);
      c.dispose();
    });
  });

  group('外注 and 人工 above 1', () {
    test('3人工 and 2.5人工 for a 外注, subtotals and grand total', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: '現場A');
      final emp = await c.addWorker(name: '山田', dayRate: 18000);
      final sub = await c.addWorker(
        name: '山田工業',
        kind: WorkerKind.contractor,
        dayRate: 25000,
      );
      expect(sub.kind, WorkerKind.contractor);
      await c.setRecord(
        workerId: emp.id,
        day: DateTime(2026, 10, 1),
        siteId: a.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: sub.id,
        day: DateTime(2026, 10, 1),
        siteId: a.id,
        units: 3,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: sub.id,
        day: DateTime(2026, 10, 2),
        siteId: a.id,
        units: 2.5,
        overtimeHours: 0,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      expect(s.hasContractor, isTrue);
      expect(s.unitsOf(WorkerKind.employee), 1);
      expect(s.amountOf(WorkerKind.employee), 18000);
      expect(s.unitsOf(WorkerKind.contractor), 5.5);
      expect(s.amountOf(WorkerKind.contractor), 137500);
      expect(s.daysOf(WorkerKind.contractor), 2);
      expect(s.units, 6.5);
      expect(s.amount, 155500);
      final sw = s.workers.last;
      expect(sw.payName, '単価');
      expect(payLabel(sub), '単価 ¥25,000');

      final text = summaryAsText(s);
      expect(text, contains('■ 従業員'));
      expect(text, contains('■ 外注'));
      expect(text, contains('従業員小計　1人工　¥18,000'));
      expect(text, contains('外注小計　5.5人工　¥137,500'));
      expect(text, contains('合計　6.5人工　¥155,500'));
      final csv = summaryAsCsv(s).trim().split('\n');
      expect(csv, contains('2026-10-01,山田工業,現場A,3,0,25000,0,75000,日当,,,昼,外注'));
      expect(csv, contains('外注小計,,,5.5,0,,,137500,,,,,外注'));
      expect(csv.last, '合計,,,6.5,0,,,155500,,,,,');

      // PDF builds with the split.
      final pdf = await c.pdfBytesFor(DateTime(2026, 10));
      expect(pdf.take(4), '%PDF'.codeUnits);
      c.dispose();
    });

    test('limits: 日当 up to 99 in 0.1 steps, 時給 and 月給 stay 0.5 or 1', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: 'A');
      final daily = await c.addWorker(name: '日当', dayRate: 10000);
      final hourly = await c.addWorker(
        name: '時給',
        payType: PayType.hourly,
        hourlyRate: 1500,
      );
      final monthly = await c.addWorker(
        name: '月給',
        payType: PayType.monthly,
        monthlySalary: 300000,
      );
      final day = DateTime(2026, 10, 1);
      Future<void> set(Worker w, double units) => c.setRecord(
        workerId: w.id,
        day: day,
        siteId: a.id,
        units: units,
        overtimeHours: 0,
        recordId: c.recordFor(w.id, day)?.id,
      );
      await set(daily, 99);
      expect(c.recordFor(daily.id, day)!.amount, 990000);
      await expectLater(set(daily, 99.5), throwsA(isA<InvalidInput>()));
      await expectLater(set(daily, 0), throwsA(isA<InvalidInput>()));
      await set(daily, 1.3);
      expect(c.recordFor(daily.id, day)!.units, 1.3);
      await expectLater(set(daily, 1.25), throwsA(isA<InvalidInput>()));
      await expectLater(set(hourly, 2), throwsA(isA<InvalidInput>()));
      await expectLater(set(monthly, 2), throwsA(isA<InvalidInput>()));
      await set(hourly, 0.5);
      expect(c.recordFor(hourly.id, day)!.amount, 1500 * 4);
      c.dispose();
    });

    test('hourly worker with 昼 + 夜勤 pays each entry by its hours', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: 'A');
      final w = await c.addWorker(
        name: '時給',
        payType: PayType.hourly,
        hourlyRate: 1500,
      );
      final day = DateTime(2026, 10, 1);
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: a.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: a.id,
        units: 0.5,
        overtimeHours: 0,
        shift: Shift.night,
      );
      final t = c.summaryFor(DateTime(2026, 10)).workers.single;
      expect(t.hours, 12);
      expect(t.amount, 18000);
      c.dispose();
    });

    test(
      'monthly salary is counted once even with several entries a day',
      () async {
        final c = await openController(directory, premium: true);
        final a = await c.addSite(name: 'A');
        final b = await c.addSite(name: 'B');
        final w = await c.addWorker(
          name: '月給',
          payType: PayType.monthly,
          monthlySalary: 300000,
        );
        final day = DateTime(2026, 10, 1);
        for (final site in [a, b]) {
          await c.setRecord(
            workerId: w.id,
            day: day,
            siteId: site.id,
            units: 0.5,
            overtimeHours: 0,
          );
        }
        final t = c.summaryFor(DateTime(2026, 10)).workers.single;
        expect(t.amount, 300000);
        expect(t.days, 1);
        c.dispose();
      },
    );

    test('free plan limits still count 職人 and 現場, not entries', () async {
      final c = await openController(directory);
      final a = await c.addSite(name: 'A');
      await c.addWorker(name: '山田', dayRate: 18000);
      await c.addWorker(
        name: '山田工業',
        kind: WorkerKind.contractor,
        dayRate: 25000,
      );
      expect(c.canAddWorker, isFalse);
      await expectLater(c.addWorker(name: '3人目'), throwsA(isA<LimitReached>()));
      for (var i = 0; i < 3; i++) {
        await c.setRecord(
          workerId: c.workers.last.id,
          day: DateTime(2026, 10, 1),
          siteId: a.id,
          units: 1.0 + i,
          overtimeHours: 0,
          recordId: c.recordFor(c.workers.last.id, DateTime(2026, 10, 1))?.id,
        );
      }
      c.dispose();
    });

    test('worker kind round-trips and changing it keeps records', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: 'A');
      final w = await c.addWorker(name: '山田工業', dayRate: 20000);
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 1),
        siteId: a.id,
        units: 3,
        overtimeHours: 0,
      );
      await c.updateWorker(id: w.id, name: '山田工業', kind: WorkerKind.contractor);
      expect(c.workerById(w.id)!.kind, WorkerKind.contractor);
      c.dispose();
      final again = await openController(directory, premium: true);
      expect(again.workers.single.kind, WorkerKind.contractor);
      expect(again.records.single.units, 3);
      again.dispose();
    });
  });

  testWidgets('worker dialog returns 外注 kind', (tester) async {
    WorkerDraft? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showWorkerDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kind-contractor')));
    await tester.pump();
    expect(find.text('会社名・屋号'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('worker-name')), '山田工業');
    await tester.enterText(find.byKey(const Key('worker-rate-daily')), '25000');
    await tester.tap(find.byKey(const Key('save-worker')));
    await tester.pumpAndSettle();
    expect(result!.kind, WorkerKind.contractor);
    expect(result!.dayRate, 25000);
  });
}
