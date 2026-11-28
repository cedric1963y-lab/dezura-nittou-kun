import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dezura_nittou/app_shell.dart';
import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/plan/entitlement.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/services/purchase_gateway.dart';
import 'package:dezura_nittou/state/app_controller.dart';

import 'support/fake_purchase_gateway.dart';
import 'support/harness.dart';

Future<AppController> fresh(
  Directory dir, {
  DateTime Function()? now,
  PurchaseGateway? purchases,
}) async {
  final c = AppController(
    repository: Repository(dir),
    purchases: purchases ?? FakePurchaseGateway(),
    loadFont: loadTestFont,
    now: now ?? testNow,
  );
  await c.load();
  return c;
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dezura_guide_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('guide shows once on first launch, swipes, and is skippable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(() => fresh(dir)))!;
    expect(c.guideSeen, isFalse);
    await tester.pumpWidget(AppShell(controller: c));
    await frames(tester);
    expect(find.text('現場と職人を登録'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('guide-pages')),
      const Offset(-600, 0),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('出面をつける'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-next')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('集計して送る'), findsOneWidget);
    expect(find.text('はじめる'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide-skip')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('guide-pages')), findsNothing);
    expect(c.guideSeen, isTrue);
    // File IO inside the widget-test zone may not persist; save explicitly.
    final c1 = (await tester.runAsync(() => fresh(dir)))!;
    await tester.runAsync(c1.markGuideSeen);
    c1.dispose();

    final c2 = (await tester.runAsync(() => fresh(dir)))!;
    expect(c2.guideSeen, isTrue);
    await tester.pumpWidget(AppShell(controller: c2, key: UniqueKey()));
    await frames(tester);
    expect(find.byKey(const Key('guide-pages')), findsNothing);
    c.dispose();
    c2.dispose();
  });

  testWidgets('existing users with data never see the guide', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final seed = (await tester.runAsync(() => fresh(dir)))!;
    await tester.runAsync(() => seed.addWorker(name: '山田'));
    seed.dispose();

    final c = (await tester.runAsync(() => fresh(dir)))!;
    expect(c.hasExistingData, isTrue);
    expect(c.guideSeen, isTrue);
    await tester.pumpWidget(AppShell(controller: c));
    await frames(tester);
    expect(find.byKey(const Key('guide-pages')), findsNothing);
    expect(find.text('現場と職人を登録'), findsNothing);
    c.dispose();
  });

  testWidgets('guide and the trial tip are not shown together', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 12, 3, 9);
    final c = (await tester.runAsync(() => fresh(dir, now: () => now)))!;
    c.entitlement = Entitlement(
      productId: PlanLimits.monthlyProductId,
      purchasedAt: now.subtract(const Duration(days: 3)),
      expiresAt: now.add(const Duration(days: 4)),
    );
    // Without the guide, this entitlement would qualify for the tip.
    expect(c.shouldShowTrialTip, isTrue);
    await tester.pumpWidget(AppShell(controller: c));
    await frames(tester);
    expect(find.text('現場と職人を登録'), findsOneWidget);
    expect(find.textContaining('お試し中のヒント'), findsNothing);
    c.dispose();
  });

  testWidgets('? buttons open a short explanation on each tab', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(() => fresh(dir)))!;
    c.guideSeen = true;
    await tester.pumpWidget(AppShell(controller: c));
    await frames(tester);
    for (final entry in {
      'tab-calendar': 'help-calendar',
      'tab-summary': 'help-summary',
      'tab-roster': 'help-roster',
      'tab-settings': 'help-settings',
    }.entries) {
      await tester.tap(find.byKey(Key(entry.key)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(Key(entry.value)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('help-close')), findsOneWidget);
      await tester.tap(find.byKey(const Key('help-close')));
      await tester.pump(const Duration(milliseconds: 400));
    }
    // Settings can reopen the guide.
    await tester.scrollUntilVisible(find.byKey(const Key('open-guide')), 300);
    await tester.tap(find.byKey(const Key('open-guide')));
    await frames(tester);
    expect(find.text('現場と職人を登録'), findsOneWidget);
    c.dispose();
  });
}
