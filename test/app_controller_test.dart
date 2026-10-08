import 'dart:io';

import 'package:dezura_nittou/errors.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/services/purchase_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_purchase_gateway.dart';
import 'support/harness.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('free plan allows 2 workers and 1 site', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北倉庫改修');
    await c.addWorker(name: '山田 太郎', dayRate: 18000);
    await c.addWorker(name: '佐藤 健', dayRate: 15000);
    expect(c.canAddWorker, isFalse);
    expect(c.canAddSite, isFalse);
    await expectLater(
      c.addWorker(name: '三人目', dayRate: 1),
      throwsA(isA<LimitReached>().having((e) => e.kind, 'kind', LimitKind.workers)),
    );
    await expectLater(
      c.addSite(name: '二つ目'),
      throwsA(isA<LimitReached>().having((e) => e.kind, 'kind', LimitKind.sites)),
    );
    c.dispose();
  });

  test('premium removes the worker and site caps', () async {
    final c = await openController(directory, premium: true);
    for (var i = 0; i < 5; i++) {
      await c.addWorker(name: '職人$i', dayRate: 15000);
      await c.addSite(name: '現場$i');
    }
    expect(c.workers.length, 5);
    expect(c.sites.length, 5);
    c.dispose();
  });

  test('one tap cycles 1人工 -> 半日 -> none and persists', () async {
    final c = await openController(directory);
    final site = await c.addSite(name: '港北倉庫改修');
    final w = await c.addWorker(name: '山田', dayRate: 18000, overtimeRate: 2500);
    final day = DateTime(2026, 10, 8);

    final first = await c.tapWorker(w.id, day);
    expect(first!.units, 1);
    expect(first.siteId, site.id);
    expect(first.dayRate, 18000);
    final second = await c.tapWorker(w.id, day);
    expect(second!.units, 0.5);
    final third = await c.tapWorker(w.id, day);
    expect(third, isNull);
    expect(c.records, isEmpty);

    await c.tapWorker(w.id, day);
    c.dispose();
    final reopened = await openController(directory);
    expect(reopened.recordFor(w.id, day)?.units, 1);
    expect(reopened.unitsByDay(DateTime(2026, 10)), {8: 1.0});
    reopened.dispose();
  });

  test('tapping needs a site', () async {
    final c = await openController(directory);
    final w = await c.addWorker(name: '山田', dayRate: 18000);
    await expectLater(
      c.tapWorker(w.id, DateTime(2026, 10, 8)),
      throwsA(isA<InvalidInput>()),
    );
    c.dispose();
  });

  test('overtime and site are set from the record sheet', () async {
    final c = await openController(directory, premium: true);
    await c.addSite(name: 'A');
    final b = await c.addSite(name: 'B');
    final w = await c.addWorker(name: '山田', dayRate: 18000, overtimeRate: 2500);
    final day = DateTime(2026, 10, 7);
    await c.setRecord(
      workerId: w.id,
      day: day,
      siteId: b.id,
      units: 1,
      overtimeHours: 2.5,
    );
    final r = c.recordFor(w.id, day)!;
    expect(r.siteId, b.id);
    expect(r.amount, 18000 + 6250);
    await expectLater(
      c.setRecord(
        workerId: w.id,
        day: day,
        siteId: b.id,
        units: 0.7,
        overtimeHours: 0,
      ),
      throwsA(isA<InvalidInput>()),
    );
    await c.clearRecord(w.id, day);
    expect(c.recordFor(w.id, day), isNull);
    c.dispose();
  });

  test('mark all adds only missing workers at the selected site', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北');
    final a = await c.addWorker(name: 'A', dayRate: 10000);
    await c.addWorker(name: 'B', dayRate: 12000);
    final day = DateTime(2026, 10, 8);
    await c.tapWorker(a.id, day);
    await c.tapWorker(a.id, day); // half day stays as is
    expect(await c.markAll(day), 1);
    expect(c.recordFor(a.id, day)!.units, 0.5);
    expect(c.recordsOn(day).length, 2);
    expect(await c.markAll(day), 0);
    c.dispose();
  });

  test('free plan is limited to the current month', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北');
    final w = await c.addWorker(name: 'A', dayRate: 10000);
    expect(c.canOpenMonth(DateTime(2026, 10)), isTrue);
    expect(c.canOpenMonth(DateTime(2026, 9)), isFalse);
    await expectLater(
      c.tapWorker(w.id, DateTime(2026, 9, 30)),
      throwsA(isA<LimitReached>().having((e) => e.kind, 'kind', LimitKind.history)),
    );
    expect(() => c.textFor(DateTime(2026, 9)), throwsA(isA<LimitReached>()));
    c.dispose();
  });

  test('PDF and CSV export are premium; text is free', () async {
    final c = await openController(directory);
    await c.addSite(name: '港北');
    final w = await c.addWorker(name: '山田', dayRate: 18000);
    await c.tapWorker(w.id, DateTime(2026, 10, 1));
    expect(c.textFor(DateTime(2026, 10)), contains('山田　1人工（1日）　¥18,000'));
    await expectLater(
      c.exportPdf(DateTime(2026, 10)),
      throwsA(isA<LimitReached>().having((e) => e.kind, 'kind', LimitKind.export)),
    );
    await expectLater(c.exportCsv(DateTime(2026, 10)), throwsA(isA<LimitReached>()));
    c.dispose();

    final p = await openController(directory, premium: true);
    final pdf = await p.exportPdf(DateTime(2026, 10));
    final csv = await p.exportCsv(DateTime(2026, 10));
    expect(File(pdf).readAsBytesSync().take(4), '%PDF'.codeUnits);
    expect(File(csv).readAsStringSync(), contains('山田'));
    p.dispose();
  });

  test('rate change applies from this month, not to closed months', () async {
    final c = await openController(directory, premium: true);
    await c.addSite(name: '港北');
    final w = await c.addWorker(name: '山田', dayRate: 18000);
    await c.tapWorker(w.id, DateTime(2026, 9, 30));
    await c.tapWorker(w.id, DateTime(2026, 10, 1));
    await c.updateWorker(id: w.id, name: '山田', dayRate: 20000);
    expect(c.recordFor(w.id, DateTime(2026, 9, 30))!.dayRate, 18000);
    expect(c.recordFor(w.id, DateTime(2026, 10, 1))!.dayRate, 20000);
    c.dispose();
  });

  test('deleting a worker or site removes its records', () async {
    final c = await openController(directory, premium: true);
    final s1 = await c.addSite(name: 'A');
    final s2 = await c.addSite(name: 'B');
    final w1 = await c.addWorker(name: '1', dayRate: 1000);
    final w2 = await c.addWorker(name: '2', dayRate: 1000);
    final day = DateTime(2026, 10, 2);
    await c.setRecord(workerId: w1.id, day: day, siteId: s1.id, units: 1, overtimeHours: 0);
    await c.setRecord(workerId: w2.id, day: day, siteId: s2.id, units: 1, overtimeHours: 0);
    await c.deleteSite(s2.id);
    expect(c.records.length, 1);
    await c.deleteWorker(w1.id);
    expect(c.records, isEmpty);
    c.dispose();
  });

  test('purchase event unlocks premium; store says none -> free', () async {
    final gateway = FakePurchaseGateway(subscriptions: []);
    final c = await openController(directory, purchases: gateway);
    expect(c.premium, isFalse);
    await gateway.emit(
      PurchaseEvent.unlocked(
        productId: PlanLimits.yearlyProductId,
        expiresAt: testNow().add(const Duration(days: 365)),
      ),
    );
    expect(c.premium, isTrue);
    expect(c.entitlement.productId, PlanLimits.yearlyProductId);
    await c.buyPlan(PlanLimits.monthlyProductId);
    expect(gateway.lastProductId, PlanLimits.monthlyProductId);
    c.dispose();

    final again = await openController(directory, purchases: FakePurchaseGateway(subscriptions: []));
    expect(again.premium, isFalse);
    again.dispose();
  });
}
