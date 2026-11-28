import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dezura_nittou/app_scope.dart';
import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/errors.dart';
import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/format.dart';
import 'package:dezura_nittou/models/plans.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:dezura_nittou/screens/calendar_screen.dart';
import 'package:dezura_nittou/screens/plan_screen.dart';
import 'package:dezura_nittou/services/plan_image.dart';
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
    test('AppInfo and pubspec are 1.0.14+18, fallback prices are new', () {
      expect(AppInfo.version, '1.0.14');
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: 1.0.14+18'));
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

  group('明日の予定', () {
    test('formatPlanTitle and file name are date-only, no money', () {
      expect(formatPlanTitle(DateTime(2026, 11, 20)), '11月20日（金）の予定');
      expect(planFileName(DateTime(2026, 11, 20)), '予定_2026年11月20日.png');
      expect(
        tomorrowOf(DateTime(2026, 11, 19, 23, 50)),
        DateTime(2026, 11, 20),
      );
    });

    test(
      'missing plans.json loads empty and does not change records',
      () async {
        write('workers.json', {
          'version': 5,
          'workers': [
            {
              'id': 'w1',
              'name': '山田',
              'kind': 'employee',
              'payType': 'daily',
              'dayRate': 18000,
              'hourlyRate': 0,
              'monthlySalary': 0,
              'overtimeRate': 2500,
              'createdAt': 1,
            },
          ],
        });
        write('sites.json', {
          'version': 5,
          'sites': [
            {
              'id': 's1',
              'name': '港北倉庫改修',
              'note': '',
              'address': '横浜市港北区新横浜2-6-1',
              'createdAt': 1,
              'isAreaSite': false,
              'areaAmountMode': 'areaTimesRate',
              'areaSqm': 0,
              'areaUnitPrice': 0,
              'contractAmount': 0,
              'settlementMonth': '',
            },
          ],
        });
        write('records.json', {
          'version': 5,
          'records': [
            {
              'id': 'r1',
              'shift': 'day',
              'workerId': 'w1',
              'day': '2026-10-08',
              'siteId': 's1',
              'payType': 'daily',
              'units': 1,
              'hours': 0,
              'overtimeHours': 0,
              'dayRate': 18000,
              'hourlyRate': 0,
              'monthlySalary': 0,
              'overtimeRate': 2500,
              'allowance': 0,
              'allowanceMemo': '',
              'transport': 0,
              'parking': 0,
            },
          ],
        });
        final c = await openController(directory);
        expect(c.plans, isEmpty);
        expect(c.records, hasLength(1));
        expect(c.records.first.dayRate, 18000);
        c.dispose();
      },
    );

    test('plans are stored apart and never change 集計 or CSV', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: '港北倉庫改修', address: '横浜市港北区新横浜2-6-1');
      final w = await c.addWorker(
        name: '山田',
        dayRate: 18000,
        overtimeRate: 2500,
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 8),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      final before = c.summaryFor(DateTime(2026, 10));
      final beforePay = before.amount;
      await c.togglePlanWorker(
        day: DateTime(2026, 10, 9),
        siteId: site.id,
        workerId: w.id,
      );
      await c.setPlanNote(
        day: DateTime(2026, 10, 9),
        siteId: site.id,
        note: '集合8時',
      );
      expect(c.planFor(DateTime(2026, 10, 9)).site(site.id).workerIds, [w.id]);
      expect(c.planFor(DateTime(2026, 10, 9)).site(site.id).note, '集合8時');
      expect(c.records, hasLength(1));
      expect(c.summaryFor(DateTime(2026, 10)).amount, beforePay);
      final csvPath = await c.exportCsv(DateTime(2026, 10));
      final csv = File(csvPath).readAsStringSync();
      expect(csv, isNot(contains('集合8時')));
      expect(File(p.join(directory.path, 'plans.json')).existsSync(), isTrue);
      final recordsFile = File(p.join(directory.path, 'records.json'));
      final decoded = jsonDecode(recordsFile.readAsStringSync()) as Map;
      expect(decoded['version'], 5);
      expect(decoded['records'], hasLength(1));
      c.dispose();
    });

    test('a worker is only on one site, and old plans are pruned', () async {
      final c = await openController(directory, premium: true);
      final a = await c.addSite(name: '現場A', address: '川崎市川崎区日進町3-1');
      final b = await c.addSite(name: '現場B');
      final w = await c.addWorker(name: '田中', dayRate: 18000);
      await c.togglePlanWorker(
        day: DateTime(2026, 10, 9),
        siteId: a.id,
        workerId: w.id,
      );
      await c.togglePlanWorker(
        day: DateTime(2026, 10, 9),
        siteId: b.id,
        workerId: w.id,
      );
      final plan = c.planFor(DateTime(2026, 10, 9));
      expect(plan.site(a.id).workerIds, isEmpty);
      expect(plan.site(b.id).workerIds, [w.id]);

      await c.savePlan(
        DayPlan(
          day: '2026-09-20',
          sites: [
            SitePlan(siteId: a.id, workerIds: [w.id]),
          ],
        ),
      );
      expect(c.plans.any((p) => p.day == '2026-09-20'), isFalse);
      expect(c.plans.any((p) => p.day == '2026-10-09'), isTrue);
      c.dispose();
    });

    test('applyPlanAsAttendance adds 1人工 and skips existing entries', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: '港北倉庫改修');
      final a = await c.addWorker(name: '山田', dayRate: 18000);
      final b = await c.addWorker(name: '田中', dayRate: 18000);
      await c.setRecord(
        workerId: a.id,
        day: DateTime(2026, 10, 9),
        siteId: site.id,
        units: 0.5,
        overtimeHours: 0,
      );
      await c.togglePlanWorker(
        day: DateTime(2026, 10, 9),
        siteId: site.id,
        workerId: a.id,
      );
      await c.togglePlanWorker(
        day: DateTime(2026, 10, 9),
        siteId: site.id,
        workerId: b.id,
      );
      final added = await c.applyPlanAsAttendance(DateTime(2026, 10, 9));
      expect(added, 1);
      expect(c.recordFor(a.id, DateTime(2026, 10, 9))!.units, 0.5);
      expect(c.recordFor(b.id, DateTime(2026, 10, 9))!.units, 1);
      expect(c.recordFor(b.id, DateTime(2026, 10, 9))!.siteId, site.id);
      c.dispose();
    });

    test('free users can make a next-month plan but cannot apply it', () async {
      final c = await openController(
        directory,
        now: () => DateTime(2026, 10, 31, 9),
      );
      final site = await c.addSite(name: '港北倉庫改修');
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      await c.togglePlanWorker(
        day: DateTime(2026, 11, 1),
        siteId: site.id,
        workerId: w.id,
      );
      expect(c.planFor(DateTime(2026, 11, 1)).isEmpty, isFalse);
      await expectLater(
        c.applyPlanAsAttendance(DateTime(2026, 11, 1)),
        throwsA(
          isA<LimitReached>().having((e) => e.kind, 'kind', LimitKind.history),
        ),
      );
      expect(c.records, isEmpty);
      c.dispose();
    });

    test('planImageContent drops unknown ids and never includes pay', () {
      const plan = DayPlan(
        day: '2026-11-20',
        sites: [
          SitePlan(siteId: 's1', workerIds: ['w1', 'gone'], note: '集合8時'),
          SitePlan(siteId: 'missing', workerIds: ['w1']),
        ],
      );
      final content = planImageContent(
        plan: plan,
        day: DateTime(2026, 11, 20),
        sites: [
          Site(
            id: 's1',
            name: '港北倉庫改修',
            note: '',
            address: '横浜市港北区新横浜2-6-1',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        workers: [
          Worker(
            id: 'w1',
            name: '山田 太郎',
            dayRate: 18000,
            overtimeRate: 2500,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        businessName: '山田工業',
      );
      expect(content.title, '11月20日（金）の予定');
      expect(content.businessName, '山田工業');
      expect(content.sites, hasLength(1));
      expect(content.sites.first.name, '港北倉庫改修');
      expect(content.sites.first.address, '横浜市港北区新横浜2-6-1');
      expect(content.sites.first.note, '集合8時');
      expect(content.sites.first.workers, ['山田 太郎']);
      final blob = [
        content.title,
        content.businessName,
        for (final s in content.sites) ...[
          s.name,
          s.address,
          s.note,
          ...s.workers,
        ],
      ].join(' ');
      expect(blob, isNot(contains('日当')));
      expect(blob, isNot(contains('¥')));
      expect(blob, isNot(contains('18000')));
    });

    testWidgets('renderPlanPng is a portrait image without money text', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final content = PlanImageContent(
          title: '11月20日（金）の予定',
          businessName: '山田工業',
          sites: const [
            PlanImageSite(
              name: '港北倉庫改修',
              address: '横浜市港北区新横浜2-6-1',
              note: '集合8時',
              workers: ['山田 太郎', '山田工業'],
            ),
          ],
        );
        final bytes = await renderPlanPng(
          content: content,
          fontData: await loadTestFont(),
        );
        expect(bytes[0], 0x89);
        expect(bytes[1], 0x50);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, planImageWidth.toInt());
        expect(
          frame.image.height,
          greaterThanOrEqualTo(planImageMinHeight.toInt()),
        );
        frame.image.dispose();
      });
    });

    testWidgets('PlanScreen defaults to tomorrow and assigns workers', (
      tester,
    ) async {
      final loaded = await tester.runAsync(() async {
        final controller = await openController(directory, premium: true);
        final site = await controller.addSite(
          name: '港北倉庫改修',
          address: '横浜市港北区新横浜2-6-1',
        );
        final worker = await controller.addWorker(
          name: '山田 太郎',
          dayRate: 18000,
        );
        return (controller, site, worker);
      });
      final c = loaded!.$1;
      final site = loaded.$2;
      final w = loaded.$3;
      await tester.pumpWidget(shell(c, const PlanScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('11月20日（金）の予定'), findsNothing);
      expect(find.text('10月9日（金）の予定'), findsOneWidget);
      expect(find.text('横浜市港北区新横浜2-6-1'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('plan-share-image')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(Key('plan-worker-${site.id}-${w.id}')));
      await tester.pump();
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          if (c
              .planFor(DateTime(2026, 10, 9))
              .site(site.id)
              .workerIds
              .contains(w.id)) {
            // Wait for savePlans to finish so notifyListeners has run.
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(c.planFor(DateTime(2026, 10, 9)).site(site.id).workerIds, [w.id]);
      // Rebuild after the real async save; the test clock does not
      // always pick up notifyListeners from runAsync.
      await tester.pumpWidget(shell(c, const PlanScreen()));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('plan-share-image')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilterChip>(
              find.byKey(Key('plan-worker-${site.id}-${w.id}')),
            )
            .selected,
        isTrue,
      );
      expect(find.text('画像でLINEに送る'), findsOneWidget);
      expect(find.text('この予定で出面をつける'), findsOneWidget);
      c.dispose();
    });

    testWidgets('calendar has a 明日の予定 button', (tester) async {
      final c = (await tester.runAsync(() => openController(directory)))!;
      await tester.pumpWidget(shell(c, const CalendarScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('open-plan')), findsOneWidget);
      expect(find.text('明日の予定'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-plan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('10月9日（金）の予定'), findsOneWidget);
      c.dispose();
    });
  });
}
