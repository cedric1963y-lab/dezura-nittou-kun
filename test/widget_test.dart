import 'dart:io';

import 'package:dezura_nittou/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// iPhone 6.1" portrait, so the whole day list is laid out.
void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_ui_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  testWidgets('empty app explains setup and the free plan', (tester) async {
    final controller = await tester.runAsync(() => openController(directory));
    await tester.pumpWidget(AppShell(controller: controller!));
    await frames(tester);

    expect(find.text('はじめに'), findsOneWidget);
    expect(find.byKey(const Key('setup-site')), findsOneWidget);
    expect(find.byKey(const Key('setup-worker')), findsOneWidget);
    expect(find.textContaining('職人2人・現場1か所'), findsOneWidget);
    expect(find.text('2026年10月'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('tapping a worker tile records 1人工 then 半日', (tester) async {
    phoneSize(tester);
    final controller = await tester.runAsync(() async {
      final c = await openController(directory);
      await c.addSite(name: '港北倉庫改修', note: '〇〇建設');
      await c.addWorker(name: '山田 太郎', dayRate: 18000);
      return c;
    });
    await tester.pumpWidget(AppShell(controller: controller!));
    await frames(tester);

    final worker = controller.workers.single;
    expect(find.text('港北倉庫改修'), findsOneWidget);
    expect(find.text('未'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(Key('worker-${worker.id}')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await frames(tester);
    final tile = find.byKey(Key('worker-${worker.id}'));
    expect(
      find.descendant(of: tile, matching: find.text('1人工')),
      findsOneWidget,
    );
    expect(find.text('1人工'), findsNWidgets(2)); // pill + day total
    expect(controller.recordFor(worker.id, DateTime(2026, 10, 8))?.units, 1);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(Key('worker-${worker.id}')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await frames(tester);
    expect(find.descendant(of: tile, matching: find.text('半日')), findsOneWidget);
    expect(find.text('0.5人工'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('summary shows totals and past months are locked', (tester) async {
    final controller = await tester.runAsync(() async {
      final c = await openController(directory);
      await c.addSite(name: '港北倉庫改修');
      final w = await c.addWorker(name: '山田 太郎', dayRate: 18000);
      await c.tapWorker(w.id, DateTime(2026, 10, 1));
      await c.tapWorker(w.id, DateTime(2026, 10, 2));
      return c;
    });
    await tester.pumpWidget(AppShell(controller: controller!, startTab: 1));
    await frames(tester);

    expect(find.text('¥36,000'), findsWidgets);
    expect(find.text('山田 太郎'), findsWidgets);

    await tester.tap(find.byKey(const Key('month-prev')).last);
    await frames(tester);
    expect(find.text('過去の月はプレミアムで見られます'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('paywall shows prices, terms, restore and legal links', (
    tester,
  ) async {
    final controller = await tester.runAsync(() => openController(directory));
    await tester.pumpWidget(AppShell(controller: controller!, startTab: 3));
    await frames(tester);

    await tester.tap(find.byKey(const Key('plan-tile')));
    await frames(tester);

    expect(find.text('月額ではじめる'), findsOneWidget);
    expect(find.text('¥100'), findsOneWidget);
    final scrollable = find.descendant(
      of: find.byType(ListView).last,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('restore')),
      300,
      scrollable: scrollable,
    );
    expect(find.text('¥1,200'), findsOneWidget);
    expect(find.textContaining('自動更新され'), findsOneWidget);
    expect(find.text('購入を復元'), findsOneWidget);
    expect(find.text('利用規約（EULA）'), findsOneWidget);
    expect(find.text('プライバシーポリシー'), findsOneWidget);
    controller.dispose();
  });
}
