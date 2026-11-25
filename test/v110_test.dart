import 'dart:io';

import 'package:dezura_nittou/app_shell.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/screens/premium_screen.dart';
import 'package:dezura_nittou/services/purchase_gateway.dart';
import 'package:dezura_nittou/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_purchase_gateway.dart';
import 'support/harness.dart';

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_110_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('version is 1.0.11+15 and StoreKit test prices match the store', () {
    expect(AppInfo.version, '1.0.11');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.0.11+15'));
    final storekit = File('ios/Runner/Products.storekit').readAsStringSync();
    expect(storekit, contains('"displayPrice" : "300"'));
    expect(storekit, contains('"displayPrice" : "3000"'));
    expect(storekit, isNot(contains('"displayPrice" : "100"')));
    expect(storekit, isNot(contains('"displayPrice" : "1200"')));
    expect(PlanLimits.monthlyPriceYen, 300);
    expect(PlanLimits.yearlyPriceYen, 3000);
  });

  testWidgets('paywall has 復元 in the app bar and keeps the bottom link', (
    tester,
  ) async {
    final controller = await tester.runAsync(() => openController(directory));
    await tester.pumpWidget(AppShell(controller: controller!, startTab: 3));
    await frames(tester);
    await tester.tap(find.byKey(const Key('plan-tile')));
    await frames(tester);

    expect(find.byType(PremiumScreen), findsOneWidget);
    expect(find.byKey(const Key('restore-appbar')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('復元')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('restore')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('restore')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('settings has a 購入を復元 row that reports nothing to restore', (
    tester,
  ) async {
    final gateway = FakePurchaseGateway();
    final controller = await tester.runAsync(
      () => openController(directory, purchases: gateway),
    );
    await tester.pumpWidget(AppShell(controller: controller!, startTab: 3));
    await frames(tester);

    expect(find.byKey(const Key('restore-settings')), findsOneWidget);
    expect(find.text('購入を復元'), findsOneWidget);

    await tester.tap(find.byKey(const Key('restore-settings')));
    await tester.pump();
    expect(gateway.restores, 1);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const Key('restore-result')), findsOneWidget);
    expect(find.text('復元できる購入はありませんでした。'), findsOneWidget);
    expect(find.text('契約したApple IDでサインインしているか確認してください。'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('app bar 復元 reports when a purchase is restored', (tester) async {
    final gateway = FakePurchaseGateway();
    final controller = await tester.runAsync(
      () => openController(directory, purchases: gateway),
    );
    await tester.pumpWidget(AppShell(controller: controller!, startTab: 3));
    await frames(tester);
    await tester.tap(find.byKey(const Key('plan-tile')));
    await frames(tester);

    expect(controller.premium, isFalse);
    await tester.tap(find.byKey(const Key('restore-appbar')));
    await tester.pump();
    expect(gateway.restores, 1);
    await tester.runAsync(() async {
      await gateway.emit(
        PurchaseEvent.unlocked(
          productId: PlanLimits.monthlyProductId,
          expiresAt: testNow().add(const Duration(days: 30)),
          restored: true,
        ),
      );
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(controller.premium, isTrue);
    expect(find.text('購入を復元しました。'), findsOneWidget);
    expect(find.text('プレミアムが有効です。'), findsOneWidget);
    controller.dispose();
  });
}
