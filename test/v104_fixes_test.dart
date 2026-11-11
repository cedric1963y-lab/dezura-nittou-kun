import 'dart:io';

import 'package:dezura_nittou/app_shell.dart';
import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/format.dart';
import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/screens/premium_screen.dart';
import 'package:dezura_nittou/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_purchase_gateway.dart';
import 'support/harness.dart';

class _FailingRepository extends Repository {
  _FailingRepository(super.root);
  bool fail = false;

  @override
  Future<void> saveWorkers(List<Worker> workers) async {
    if (fail) throw const FileSystemException('disk full');
    return super.saveWorkers(workers);
  }

  @override
  Future<void> saveSites(List<Site> sites) async {
    if (fail) throw const FileSystemException('disk full');
    return super.saveSites(sites);
  }
}

DayRecord _rec(String day) => DayRecord(
  workerId: 'w1',
  day: day,
  siteId: 's1',
  units: 1,
  overtimeHours: 0,
  dayRate: 18000,
  overtimeRate: 0,
);

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_104_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('periodEnd stays in the next month', () {
    test('Jan 31 monthly -> Feb 28', () {
      final end = PlanLimits.periodEnd(
        PlanLimits.monthlyProductId,
        DateTime(2027, 1, 31, 10),
      );
      expect(end, DateTime(2027, 2, 28, 10));
    });
    test('leap year Jan 31 -> Feb 29, Feb 29 yearly -> Feb 28', () {
      expect(
        PlanLimits.periodEnd(PlanLimits.monthlyProductId, DateTime(2028, 1, 31)),
        DateTime(2028, 2, 29),
      );
      expect(
        PlanLimits.periodEnd(PlanLimits.yearlyProductId, DateTime(2028, 2, 29)),
        DateTime(2029, 2, 28),
      );
    });
    test('normal day unchanged', () {
      expect(
        PlanLimits.periodEnd(PlanLimits.monthlyProductId, DateTime(2026, 10, 8)),
        DateTime(2026, 11, 8),
      );
    });
  });

  test('blank names show ？ and bad day keys are skipped', () {
    expect(nameInitial(''), '？');
    expect(nameInitial('   '), '？');
    expect(nameInitial('山田 太郎'), '山');
    expect(tryParseDayKey('2026-10-08'), DateTime(2026, 10, 8));
    expect(tryParseDayKey('2026-10-xx'), isNull);
    expect(tryParseDayKey('2026-02-30'), isNull);
    expect(tryParseDayKey('broken'), isNull);

    final created = DateTime(2026, 9, 1);
    final summary = summarizeMonth(
      month: DateTime(2026, 10),
      workers: [
        Worker(
          id: 'w1',
          name: '山田 太郎',
          dayRate: 18000,
          overtimeRate: 0,
          createdAt: created,
        ),
      ],
      sites: [Site(id: 's1', name: '港北倉庫改修', note: '', createdAt: created)],
      records: [_rec('2026-10-08'), _rec('2026-10-xx')],
    );
    expect(summary.records.length, 1);
    expect(summary.workers.single.unitsByDay, {8: 1.0});
  });

  test('calendar badges skip a bad day key', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北倉庫改修');
    await c.addWorker(name: '山田 太郎', dayRate: 18000);
    final w = c.workers.single.id;
    final s = c.sites.single.id;
    c.records = [
      for (final day in ['2026-10-08', '2026-10-??'])
        DayRecord(
          workerId: w,
          day: day,
          siteId: s,
          units: 1,
          overtimeHours: 0,
          dayRate: 18000,
          overtimeRate: 0,
        ),
    ];
    expect(c.unitsByDay(DateTime(2026, 10)), {8: 1.0});
    c.dispose();
  });

  test('failed save leaves workers and sites unchanged', () async {
    final repo = _FailingRepository(directory);
    await repo.init();
    final c = AppController(
      repository: repo,
      purchases: FakePurchaseGateway(),
      loadFont: loadTestFont,
      now: testNow,
    );
    await c.load();
    repo.fail = true;
    await expectLater(
      c.addWorker(name: '山田 太郎', dayRate: 18000),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(c.addSite(name: '港北倉庫改修'), throwsA(anything));
    expect(c.workers, isEmpty);
    expect(c.sites, isEmpty);
    repo.fail = false;
    await c.addWorker(name: '山田 太郎', dayRate: 18000);
    expect(c.workers.length, 1);
    c.dispose();
  });

  for (final scale in [1.3, 1.5]) {
    testWidgets('calendar fits 375x667 at text scale $scale', (tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await tester.runAsync(() async {
        final c = await openController(directory);
        await c.addSite(name: '港北倉庫改修');
        await c.addWorker(name: '山田 太郎', dayRate: 18000);
        await c.addWorker(name: '', dayRate: 1).catchError((_) => c.workers.first);
        for (var d = 1; d <= 8; d++) {
          await c.tapWorker(c.workers.first.id, DateTime(2026, 10, d));
        }
        return c;
      });
      await tester.pumpWidget(AppShell(controller: controller!));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('day-8')), findsOneWidget);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  }

  testWidgets('paywall without store products blocks purchase', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final gateway = FakePurchaseGateway(products: const []);
    final controller = await tester.runAsync(
      () => openController(directory, purchases: gateway),
    );
    await tester.pumpWidget(AppShell(controller: controller!, startTab: 3));
    await tester.pump();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const PremiumScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text(PlanLimits.productsUnavailableMessage), findsOneWidget);
    expect(find.text('¥100'), findsNothing);
    expect(find.text('¥1,200'), findsNothing);
    final monthly = tester.widget<FilledButton>(
      find.byKey(const Key('buy-monthly')),
    );
    expect(monthly.onPressed, isNull);
    final yearly = tester.widget<OutlinedButton>(
      find.byKey(const Key('buy-yearly')),
    );
    expect(yearly.onPressed, isNull);
    expect(find.textContaining('App Store Connect'), findsNothing);
    expect(find.textContaining('jp.dezura.app'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('restore')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    final restore = tester.widget<TextButton>(find.byKey(const Key('restore')));
    expect(restore.onPressed, isNotNull);
    expect(find.byKey(const Key('link-terms')), findsOneWidget);
    expect(find.byKey(const Key('link-privacy')), findsOneWidget);
    expect(gateway.buys, 0);
    controller.dispose();
  });
}
