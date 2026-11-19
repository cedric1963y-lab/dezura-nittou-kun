import 'dart:convert';
import 'dart:io';

import 'package:dezura_nittou/app_scope.dart';
import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/errors.dart';
import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/screens/record_sheet.dart';
import 'package:dezura_nittou/screens/summary_screen.dart';
import 'package:dezura_nittou/services/links.dart';
import 'package:dezura_nittou/state/app_controller.dart';
import 'package:dezura_nittou/theme.dart';
import 'package:dezura_nittou/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_108_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  void write(String name, Map<String, dynamic> json) {
    directory.createSync(recursive: true);
    File(p.join(directory.path, name)).writeAsStringSync(jsonEncode(json));
  }

  Widget shell(AppController c, Widget home) {
    return AppScope(
      controller: c,
      child: MaterialApp(
        theme: buildTheme(),
        locale: const Locale('ja'),
        supportedLocales: const [Locale('ja')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );
  }

  group('version and prices', () {
    test('AppInfo and pubspec are 1.0.8+11, fallback prices are new', () {
      expect(AppInfo.version, '1.0.8');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 1.0.8+11'));
      expect(PlanLimits.monthlyPriceYen, 300);
      expect(PlanLimits.yearlyPriceYen, 3000);
      expect(PlanLimits.monthlyPriceLabel, '¥300');
      expect(PlanLimits.yearlyPriceLabel, '¥3,000');
      expect(Repository.listSchemaVersion, 5);
    });
  });

  group('住所', () {
    test('maps URL encodes the address and ignores blanks', () {
      expect(
        appleMapsUri('横浜市港北区新横浜2-6-1')!.toString(),
        'https://maps.apple.com/?q=%E6%A8%AA%E6%B5%9C%E5%B8%82%E6%B8%AF%E5%8C%97%E5%8C%BA%E6%96%B0%E6%A8%AA%E6%B5%9C2-6-1',
      );
      expect(appleMapsUri('  '), isNull);
      expect(appleMapsUri(''), isNull);
    });

    test('optional 住所 is saved, shown, and missing files stay empty', () async {
      write('sites.json', {
        'version': 4,
        'sites': [
          {'id': 's-old', 'name': '旧現場', 'note': 'メモ', 'createdAt': 0},
        ],
      });
      final c = await openController(directory, premium: true);
      expect(c.sites.single.address, '');
      expect(c.sites.single.name, '旧現場');

      final site = await c.addSite(name: '港北倉庫改修', address: '横浜市港北区新横浜2-6-1');
      expect(site.address, '横浜市港北区新横浜2-6-1');
      await c.updateSite(id: site.id, name: site.name, address: '川崎市川崎区日進町3-1');
      expect(c.siteById(site.id)!.address, '川崎市川崎区日進町3-1');
      await c.updateSite(id: site.id, name: site.name, address: '');
      expect(c.siteById(site.id)!.address, '');

      final saved = jsonDecode(
        File(p.join(directory.path, 'sites.json')).readAsStringSync(),
      );
      expect(saved['version'], 5);
      expect(
        saved['sites'].firstWhere((s) => s['id'] == 's-old')['address'],
        '',
      );
      c.dispose();
    });

    test('too long 住所 is rejected; existing sites stay unchanged', () async {
      final c = await openController(directory, premium: true);
      await expectLater(
        c.addSite(name: '港北', address: 'あ' * (maxSiteAddressLength + 1)),
        throwsA(isA<InvalidInput>()),
      );
      expect(c.sites, isEmpty);
      c.dispose();
    });
  });

  group('人工 0.1 steps', () {
    test('日当 and 外注 accept 0.1 steps, 時給 and 月給 stay 1 or 0.5', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: '港北');
      final daily = await c.addWorker(name: '山田', dayRate: 18000);
      final crew = await c.addWorker(
        name: '山田工業',
        dayRate: 18000,
        kind: WorkerKind.contractor,
      );
      final hourly = await c.addWorker(
        name: '時給の人',
        payType: PayType.hourly,
        hourlyRate: 1500,
      );
      final monthly = await c.addWorker(
        name: '月給の人',
        payType: PayType.monthly,
        monthlySalary: 300000,
      );
      final day = DateTime(2026, 10, 7);

      await c.setRecord(
        workerId: daily.id,
        day: day,
        siteId: site.id,
        units: 1.1,
        overtimeHours: 0,
      );
      expect(c.records.single.units, 1.1);
      expect(c.records.single.amount, 19800);

      // 0.1 + 0.2 float noise is accepted and stored as 0.3.
      await c.setRecord(
        workerId: daily.id,
        day: day,
        siteId: site.id,
        units: 0.1 + 0.2,
        overtimeHours: 0,
        recordId: c.records.single.id,
      );
      expect(c.recordById(c.records.single.id)!.units, 0.3);

      await c.setRecord(
        workerId: crew.id,
        day: day,
        siteId: site.id,
        units: 1.2,
        overtimeHours: 0,
      );
      expect(c.records.where((r) => r.workerId == crew.id).single.units, 1.2);

      await expectLater(
        c.setRecord(
          workerId: daily.id,
          day: day,
          siteId: site.id,
          units: 0.15,
          overtimeHours: 0,
          recordId: c.records.where((r) => r.workerId == daily.id).single.id,
        ),
        throwsA(isA<InvalidInput>()),
      );
      await expectLater(
        c.setRecord(
          workerId: hourly.id,
          day: day,
          siteId: site.id,
          units: 1.1,
          overtimeHours: 0,
        ),
        throwsA(isA<InvalidInput>()),
      );
      await expectLater(
        c.setRecord(
          workerId: monthly.id,
          day: day,
          siteId: site.id,
          units: 1.2,
          overtimeHours: 0,
        ),
        throwsA(isA<InvalidInput>()),
      );
      await c.setRecord(
        workerId: hourly.id,
        day: day,
        siteId: site.id,
        units: 0.5,
        overtimeHours: 0,
      );
      expect(c.records.where((r) => r.workerId == hourly.id).single.units, 0.5);
      c.dispose();
    });

    test('one-tap cycle still goes 1.2 -> 1 -> 0.5 -> none', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: '港北');
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      final day = DateTime(2026, 10, 7);
      await c.setRecord(
        workerId: w.id,
        day: day,
        siteId: site.id,
        units: 1.2,
        overtimeHours: 0,
      );
      expect((await c.tapWorker(w.id, day))!.units, 1);
      expect((await c.tapWorker(w.id, day))!.units, 0.5);
      expect(await c.tapWorker(w.id, day), isNull);
      c.dispose();
    });

    test('平米割り still splits in proportion with 0.1 人工', () {
      expect(splitByUnits(10000, [1.1, 0.9]), [5500, 4500]);
      expect(splitByUnits(10000, [1.2, 1.8]).reduce((a, b) => a + b), 10000);
    });

    test('quick picks are 0.5, 1, 1.2, 1.5, 2', () {
      expect(dailyUnitQuickPicks, [0.5, 1.0, 1.2, 1.5, 2.0]);
      expect(dailyUnitStep, 0.1);
    });
  });

  group('widgets', () {
    testWidgets('site dialog has 住所（任意） and keeps it on save', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      SiteDraft? draft;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          locale: const Locale('ja'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                key: const Key('open-site'),
                onPressed: () async {
                  draft = await showSiteDialog(
                    context,
                    now: DateTime(2026, 10, 8),
                  );
                },
                child: const Text('開く'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-site')));
      await tester.pumpAndSettle();
      expect(find.text('住所（任意）'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('site-name')), '港北倉庫改修');
      await tester.enterText(
        find.byKey(const Key('site-address')),
        '横浜市港北区新横浜2-6-1',
      );
      await tester.tap(find.byKey(const Key('save-site')));
      await tester.pumpAndSettle();
      expect(draft, isNotNull);
      expect(draft!.name.trim(), '港北倉庫改修');
      expect(draft!.address.trim(), '横浜市港北区新横浜2-6-1');
    });

    testWidgets('日当 sheet uses 0.1 steps and the new chips', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final c = await tester.runAsync(() async {
        final controller = await openController(directory, premium: true);
        final site = await controller.addSite(name: '港北');
        final w = await controller.addWorker(name: '山田', dayRate: 18000);
        await controller.setRecord(
          workerId: w.id,
          day: DateTime(2026, 10, 8),
          siteId: site.id,
          units: 1,
          overtimeHours: 0,
        );
        return controller;
      });

      await tester.pumpWidget(shell(c!, const SizedBox.shrink()));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SizedBox));
      showRecordSheet(
        context,
        worker: c.workers.single,
        day: DateTime(2026, 10, 8),
        recordId: c.records.single.id,
      );
      await tester.pumpAndSettle();

      expect(find.text('1人工'), findsWidgets);
      expect(find.byKey(const Key('units-1.2')), findsOneWidget);
      expect(find.byKey(const Key('units-1.5')), findsOneWidget);
      expect(find.byKey(const Key('units-2.0')), findsOneWidget);
      expect(find.byKey(const Key('units-3.0')), findsNothing);
      expect(find.byKey(const Key('units-5.0')), findsNothing);
      expect(find.byKey(const Key('units-10.0')), findsNothing);

      await tester.tap(find.byKey(const Key('units-plus')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('units-value')), findsOneWidget);
      expect(find.text('1.1人工'), findsOneWidget);

      await tester.tap(find.byKey(const Key('units-1.2')));
      await tester.pumpAndSettle();
      expect(find.text('1.2人工'), findsOneWidget);
      c.dispose();
    });

    testWidgets('集計 shows a site address only when it is set', (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final c = await tester.runAsync(() async {
        final controller = await openController(directory, premium: true);
        final withAddress = await controller.addSite(
          name: '港北倉庫改修',
          address: '横浜市港北区新横浜2-6-1',
        );
        final noAddress = await controller.addSite(name: '南区マンション');
        final w = await controller.addWorker(name: '山田', dayRate: 18000);
        await controller.setRecord(
          workerId: w.id,
          day: DateTime(2026, 10, 1),
          siteId: withAddress.id,
          units: 1.1,
          overtimeHours: 0,
        );
        await controller.setRecord(
          workerId: w.id,
          day: DateTime(2026, 10, 2),
          siteId: noAddress.id,
          units: 1,
          overtimeHours: 0,
        );
        return controller;
      });

      await tester.pumpWidget(shell(c!, const SummaryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('横浜市港北区新横浜2-6-1'), findsOneWidget);
      expect(
        find.byKey(Key('site-address-${c.sites.first.id}')),
        findsOneWidget,
      );
      expect(find.text('1.1人工・1人'), findsOneWidget);
      // The site without an address has no map row.
      expect(find.byKey(Key('site-address-${c.sites[1].id}')), findsNothing);
      c.dispose();
    });
  });
}
