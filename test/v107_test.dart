import 'dart:convert';
import 'dart:io';

import 'package:dezura_nittou/app_scope.dart';
import 'package:dezura_nittou/data/repository.dart';
import 'package:dezura_nittou/format.dart';
import 'package:dezura_nittou/logic/summary.dart';
import 'package:dezura_nittou/models/records.dart';
import 'package:dezura_nittou/plan/limits.dart';
import 'package:dezura_nittou/screens/settings_screen.dart';
import 'package:dezura_nittou/screens/summary_screen.dart';
import 'package:dezura_nittou/services/toolbox.dart';
import 'package:dezura_nittou/state/app_controller.dart';
import 'package:dezura_nittou/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dezura_107_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  void write(String name, Map<String, dynamic> json) {
    directory.createSync(recursive: true);
    File(p.join(directory.path, name)).writeAsStringSync(jsonEncode(json));
  }

  group('splitByUnits', () {
    test('shares sum to the total (largest remainder)', () {
      expect(splitByUnits(100000, [1, 0.5, 0.5]), [50000, 25000, 25000]);
      final thirds = splitByUnits(10000, [1, 1, 1]);
      expect(thirds.reduce((a, b) => a + b), 10000);
      expect(thirds, [3334, 3333, 3333]);
      expect(splitByUnits(0, [1, 1]), [0, 0]);
      expect(splitByUnits(1000, const <double>[]), isEmpty);
      expect(splitByUnits(1000, [0, 0]), [0, 0]);
    });
  });

  group('平米割り', () {
    test('splits a 請負額 by 人工 and charges no 日当', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(
        name: '平米現場',
        isAreaSite: true,
        areaAmountMode: AreaAmountMode.contract,
        contractAmount: 100000,
        settlementMonth: '2026-10',
      );
      final a = await c.addWorker(name: '山田', dayRate: 18000);
      final b = await c.addWorker(name: '佐藤', dayRate: 20000);
      await c.setRecord(
        workerId: a.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: b.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 0.5,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: b.id,
        day: DateTime(2026, 10, 2),
        siteId: site.id,
        units: 0.5,
        overtimeHours: 0,
      );
      // 山田 1人工, 佐藤 1人工 → 50,000 each. Stored day rates are ignored.
      final s = c.summaryFor(DateTime(2026, 10));
      expect(s.hasArea, isTrue);
      expect(s.areaTotal, 100000);
      expect(s.wageTotal, 0);
      expect(s.amount, 100000);
      final y = s.workers.firstWhere((w) => w.worker.id == a.id);
      final t = s.workers.firstWhere((w) => w.worker.id == b.id);
      expect(y.wageAmount, 0);
      expect(y.areaAmount, 50000);
      expect(y.amount, 50000);
      expect(t.wageAmount, 0);
      expect(t.areaAmount, 50000);
      expect(t.units, 1);
      final recap = s.records.where((r) => r.workerId == a.id).single;
      expect(recap.amount, 18000); // stored 日当 is unchanged
      expect(wageOf(recap, site), 0);
      expect(s.sites.single.amount, 100000);
      expect(s.sites.single.areaAmount, 100000);

      final text = summaryAsText(s);
      expect(text, contains('└ 平米割り　¥50,000'));
      expect(text, isNot(contains('└ 色付け')));
      expect(text, contains(areaSiteNote));
      final csv = summaryAsCsv(s);
      expect(csv, contains('2026-10,山田,,,,,,50000,平米割り,,,,従業員'));
      expect(csv, isNot(contains('色付け')));
      // Record rows show 0 yen, no 日当 rate.
      expect(csv, contains('2026-10-01,山田,平米現場,1,0,,,0,日当,,,昼,従業員'));
      c.dispose();
    });

    test('平米数×単価 and a 外注 multi-人工 are split in proportion', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(
        name: 'A',
        isAreaSite: true,
        areaSqm: 100,
        areaUnitPrice: 3000,
        settlementMonth: '2026-10',
      );
      expect(site.areaTotal, 300000);
      final emp = await c.addWorker(name: '山田', dayRate: 18000);
      final sub = await c.addWorker(
        name: '山田工業',
        kind: WorkerKind.contractor,
        dayRate: 25000,
      );
      await c.setRecord(
        workerId: emp.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: sub.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 2,
        overtimeHours: 0,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      // 1 : 2 → 100,000 and 200,000. No 日当.
      expect(s.amount, 300000);
      expect(
        s.workers.firstWhere((w) => w.worker.id == emp.id).areaAmount,
        100000,
      );
      expect(
        s.workers.firstWhere((w) => w.worker.id == sub.id).areaAmount,
        200000,
      );
      expect(s.wageTotal, 0);
      c.dispose();
    });

    test('month-spanning work is paid only in the chosen 集計月', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(
        name: '跨月',
        isAreaSite: true,
        areaAmountMode: AreaAmountMode.contract,
        contractAmount: 90000,
        settlementMonth: '2026-11',
      );
      final a = await c.addWorker(name: '山田', dayRate: 18000);
      final b = await c.addWorker(name: '佐藤', dayRate: 18000);
      await c.setRecord(
        workerId: a.id,
        day: DateTime(2026, 10, 20),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: a.id,
        day: DateTime(2026, 11, 5),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      await c.setRecord(
        workerId: b.id,
        day: DateTime(2026, 11, 6),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      // 山田 2人工 (Oct+Nov), 佐藤 1人工 → 60,000 and 30,000 in November only.
      final oct = c.summaryFor(DateTime(2026, 10));
      expect(oct.units, 1);
      expect(oct.amount, 0);
      expect(oct.hasArea, isFalse);
      expect(oct.workers.single.worker.id, a.id);
      expect(oct.workers.single.areaAmount, 0);
      expect(oct.sites.single.amount, 0);

      final nov = c.summaryFor(DateTime(2026, 11));
      expect(nov.hasArea, isTrue);
      expect(nov.areaTotal, 90000);
      expect(nov.amount, 90000);
      expect(
        nov.workers.firstWhere((w) => w.worker.id == a.id).areaAmount,
        60000,
      );
      expect(nov.workers.firstWhere((w) => w.worker.id == a.id).units, 1);
      expect(
        nov.workers.firstWhere((w) => w.worker.id == b.id).areaAmount,
        30000,
      );
      // October 人工 still counts toward the split, shown as allUnits.
      expect(nov.sites.single.allUnits, 3);
      expect(nov.sites.single.units, 2);
      c.dispose();
    });

    test('a 日当 site next to a 平米 site is unchanged', () async {
      final c = await openController(directory, premium: true);
      final daily = await c.addSite(name: '日当現場');
      final area = await c.addSite(
        name: '平米現場',
        isAreaSite: true,
        areaAmountMode: AreaAmountMode.contract,
        contractAmount: 40000,
        settlementMonth: '2026-10',
      );
      final w = await c.addWorker(
        name: '山田',
        dayRate: 18000,
        overtimeRate: 2500,
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 1),
        siteId: daily.id,
        units: 1,
        overtimeHours: 2,
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 2),
        siteId: area.id,
        units: 1,
        overtimeHours: 0,
        shift: Shift.night,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      final total = s.workers.single;
      expect(total.wageAmount, 18000 + 5000);
      expect(total.areaAmount, 40000);
      expect(total.amount, 18000 + 5000 + 40000);
      expect(s.sites.firstWhere((x) => x.site.id == daily.id).amount, 23000);
      expect(s.sites.firstWhere((x) => x.site.id == area.id).amount, 40000);
      c.dispose();
    });
  });

  group('色付け', () {
    test('is a separate total from 日当, hidden when unused', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: 'A');
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
        allowance: 3000,
        allowanceMemo: '搬入が大変',
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 2),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      expect(s.hasAllowance, isTrue);
      expect(s.allowanceTotal, 3000);
      expect(s.wageTotal, 36000);
      expect(s.amount, 39000);
      expect(s.workers.single.allowance, 3000);
      final text = summaryAsText(s);
      expect(text, contains('└ 日当　¥36,000'));
      expect(text, contains('└ 色付け　¥3,000'));
      expect(text, isNot(contains('平米割り')));
      final csv = summaryAsCsv(s);
      expect(
        csv,
        startsWith(
          '\uFEFF日付,職人,現場,人工,残業時間,日当,残業単価,金額,区分,勤務時間,時給,昼夜,従業員外注,色付け,色付けメモ',
        ),
      );
      expect(
        csv,
        contains('2026-10-01,山田,A,1,0,18000,0,18000,日当,,,昼,従業員,3000,搬入が大変'),
      );
      expect(csv, contains('2026-10-02,山田,A,1,0,18000,0,18000,日当,,,昼,従業員,,'));
      expect(csv, contains('合計,,,2,0,,,39000,,,,,,,'));
      c.dispose();
    });

    test(
      '色付け on a 平米 site is added on top of the split, still no 日当',
      () async {
        final c = await openController(directory, premium: true);
        final site = await c.addSite(
          name: 'A',
          isAreaSite: true,
          areaAmountMode: AreaAmountMode.contract,
          contractAmount: 10000,
          settlementMonth: '2026-10',
        );
        final w = await c.addWorker(name: '山田', dayRate: 18000);
        await c.setRecord(
          workerId: w.id,
          day: DateTime(2026, 10, 1),
          siteId: site.id,
          units: 1,
          overtimeHours: 0,
          allowance: 2000,
          allowanceMemo: '残作業',
        );
        final s = c.summaryFor(DateTime(2026, 10));
        expect(s.wageTotal, 0);
        expect(s.areaTotal, 10000);
        expect(s.allowanceTotal, 2000);
        expect(s.amount, 12000);
        c.dispose();
      },
    );
  });

  group('migration', () {
    test('v3 files load with no 平米 and no 色付け, amounts unchanged', () async {
      write('workers.json', {
        'version': 3,
        'workers': [
          {
            'id': 'w1',
            'name': '山田 太郎',
            'kind': 'employee',
            'payType': 'daily',
            'dayRate': 18000,
            'hourlyRate': 0,
            'monthlySalary': 0,
            'overtimeRate': 2500,
            'createdAt': 0,
          },
        ],
      });
      write('sites.json', {
        'version': 3,
        'sites': [
          {'id': 's1', 'name': '港北', 'note': '', 'createdAt': 0},
        ],
      });
      write('records.json', {
        'version': 3,
        'records': [
          {
            'id': 'r1',
            'shift': 'day',
            'workerId': 'w1',
            'day': '2026-10-01',
            'siteId': 's1',
            'payType': 'daily',
            'units': 1,
            'hours': 0,
            'overtimeHours': 2,
            'dayRate': 18000,
            'hourlyRate': 0,
            'monthlySalary': 0,
            'overtimeRate': 2500,
          },
        ],
      });
      final c = await openController(directory, premium: true);
      expect(c.sites.single.isAreaSite, isFalse);
      expect(c.sites.single.address, '');
      expect(c.sites.single.areaTotal, 0);
      expect(c.records.single.allowance, 0);
      expect(c.records.single.allowanceMemo, '');
      expect(c.records.single.transport, 0);
      expect(c.records.single.parking, 0);
      final s = c.summaryFor(DateTime(2026, 10));
      expect(s.amount, 18000 + 5000);
      expect(s.hasArea, isFalse);
      expect(s.hasAllowance, isFalse);
      expect(s.hasTransport, isFalse);
      expect(s.hasParking, isFalse);
      expect(summaryAsText(s), isNot(contains('色付け')));
      expect(summaryAsText(s), isNot(contains('交通費')));
      expect(summaryAsText(s), isNot(contains('駐車場代')));
      expect(summaryAsText(s), isNot(contains('平米割り')));

      // Saving records rewrites them in the current schema. sites.json
      // stays at v3 until a site is saved, and still loads as a non-平米
      // site with an empty 住所.
      await c.tapWorker('w1', DateTime(2026, 10, 3));
      final sitesBefore = jsonDecode(
        File(p.join(directory.path, 'sites.json')).readAsStringSync(),
      );
      final records = jsonDecode(
        File(p.join(directory.path, 'records.json')).readAsStringSync(),
      );
      expect(sitesBefore['version'], 3);
      expect(records['version'], Repository.listSchemaVersion);
      expect(records['records'][0]['allowance'], 0);
      expect(records['records'][0]['transport'], 0);
      expect(records['records'][0]['parking'], 0);
      await c.updateSite(id: 's1', name: '港北');
      final sites = jsonDecode(
        File(p.join(directory.path, 'sites.json')).readAsStringSync(),
      );
      expect(sites['version'], Repository.listSchemaVersion);
      expect(sites['sites'][0]['isAreaSite'], isFalse);
      expect(sites['sites'][0]['address'], '');
      c.dispose();
      final again = await openController(directory, premium: true);
      expect(again.summaryFor(DateTime(2026, 10)).amount, 18000 + 5000 + 18000);
      expect(again.records.first.allowance, 0);
      expect(again.sites.single.isAreaSite, isFalse);
      again.dispose();
    });
  });

  group('交通費・駐車場代', () {
    test('are separate 経費 from 日当 and 色付け, hidden when unused', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: 'A');
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
        transport: 800,
        parking: 1500,
      );
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 2),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      expect(s.hasTransport, isTrue);
      expect(s.hasParking, isTrue);
      expect(s.transportTotal, 800);
      expect(s.parkingTotal, 1500);
      expect(s.wageTotal, 36000);
      expect(s.amount, 38300);
      final text = summaryAsText(s);
      expect(text, contains('└ 日当　¥36,000'));
      expect(text, contains('└ 交通費　¥800'));
      expect(text, contains('└ 駐車場代　¥1,500'));
      expect(text, isNot(contains('色付け')));
      final csv = summaryAsCsv(s);
      expect(
        csv,
        startsWith(
          '\uFEFF日付,職人,現場,人工,残業時間,日当,残業単価,金額,区分,勤務時間,時給,昼夜,従業員外注,交通費,駐車場代',
        ),
      );
      expect(
        csv,
        contains('2026-10-01,山田,A,1,0,18000,0,18000,日当,,,昼,従業員,800,1500'),
      );
      expect(csv, contains('2026-10-02,山田,A,1,0,18000,0,18000,日当,,,昼,従業員,,'));
      expect(csv, contains('合計,,,2,0,,,38300,,,,,,,'));
      c.dispose();
    });

    test('経費 on a 平米 site is added on top of the split, still no 日当', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(
        name: 'A',
        isAreaSite: true,
        areaAmountMode: AreaAmountMode.contract,
        contractAmount: 10000,
        settlementMonth: '2026-10',
      );
      final w = await c.addWorker(name: '山田', dayRate: 18000);
      await c.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
        transport: 500,
        parking: 1000,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      expect(s.wageTotal, 0);
      expect(s.areaTotal, 10000);
      expect(s.transportTotal, 500);
      expect(s.parkingTotal, 1000);
      expect(s.amount, 11500);
      expect(summaryAsText(s), isNot(contains('└ 日当')));
      c.dispose();
    });
  });

  group('個人明細', () {
    test('workerDayLines include only that worker, with 経費 and 平米 share on the total', () async {
      final c = await openController(directory, premium: true);
      final site = await c.addSite(name: 'A');
      final a = await c.addWorker(name: 'Aさん', dayRate: 20000);
      final b = await c.addWorker(name: 'Bさん', dayRate: 18000);
      await c.setRecord(
        workerId: a.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
        allowance: 2000,
        transport: 800,
        parking: 1000,
      );
      await c.setRecord(
        workerId: b.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
        transport: 300,
      );
      final s = c.summaryFor(DateTime(2026, 10));
      final lines = workerDayLines(s, a.id);
      expect(lines, hasLength(1));
      expect(lines.single.record.workerId, a.id);
      expect(lines.single.wage, 20000);
      expect(lines.single.allowance, 2000);
      expect(lines.single.transport, 800);
      expect(lines.single.parking, 1000);
      expect(lines.single.amount, 23800);
      expect(workerDayLines(s, b.id).single.amount, 18300);
      expect(s.workers.where((w) => w.worker.id == a.id).single.amount, 23800);
      expect(
        exportWorkerFileName(DateTime(2026, 10), 'Aさん', 'pdf'),
        '出面日当_2026年10月_Aさん.pdf',
      );
      c.dispose();
    });
  });

  group('version and 道具箱', () {
    test('AppInfo is shown from the current package version', () {
      expect(AppInfo.version, isNotEmpty);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('version: ${AppInfo.version}'));
    });

    test('職人の道具箱 lists the other construction apps, 見積 first then 工程表', () {
      expect(ConstructionApps.others.length, 6);
      expect(ConstructionApps.others.first, ConstructionApps.mitsumori);
      expect(ConstructionApps.others[1], ConstructionApps.koutei);
      expect(ConstructionApps.mitsumori.id, 6820367399);
      expect(ConstructionApps.koutei.id, 6836845198);
      expect(ConstructionApps.koutei.name, '工事の工程表');
      expect(ConstructionApps.koutei.blurb, '現場の工程を帯で見て、雨の順延もまとめてずらす');
      expect(ConstructionApps.koutei.storeUrl, 'https://apps.apple.com/jp/app/id6836845198');
      expect(ConstructionApps.shashinNippo.id, 6820176592);
      expect(ConstructionApps.shokocho.id, 6819914622);
      expect(ConstructionApps.zaiseki.id, 6816288691);
      expect(ConstructionApps.nurimenseki.id, 6813789213);
      expect(ConstructionApps.others.map((a) => a.id).toSet().length, 6);
      expect(ConstructionApps.others.any((a) => a.id == 6820335056), isFalse);
    });
  });

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

  testWidgets('設定 shows 職人の道具箱, 集計 shows the 見積 prompt when there is data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final c = await tester.runAsync(() async {
      final controller = await openController(directory, premium: true);
      final site = await controller.addSite(name: '港北');
      final w = await controller.addWorker(name: '山田', dayRate: 18000);
      await controller.setRecord(
        workerId: w.id,
        day: DateTime(2026, 10, 1),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
      );
      return controller;
    });

    await tester.pumpWidget(shell(c!, const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('職人の道具箱'), findsOneWidget);
    expect(find.text('かんたん見積・請求くん'), findsOneWidget);
    expect(find.text('工事の工程表'), findsOneWidget);
    expect(find.text('現場の工程を帯で見て、雨の順延もまとめてずらす'), findsOneWidget);
    expect(find.byKey(const Key('toolbox-6836845198')), findsOneWidget);
    expect(find.text('写真日報くん'), findsOneWidget);
    expect(find.text('仕事の証拠帳'), findsOneWidget);
    expect(find.text('現場材積くん'), findsOneWidget);
    expect(find.text('塗り面積くん'), findsOneWidget);
    expect(find.byKey(const Key('toolbox-6820335056')), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining(AppInfo.version),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.textContaining(AppInfo.version), findsOneWidget);

    await tester.pumpWidget(shell(c, const SummaryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('月末の集計を、見積に使う'), findsOneWidget);
    expect(find.byKey(const Key('mitsumori-prompt')), findsOneWidget);
    expect(find.text('共有'), findsWidgets);
    c.dispose();
  });
}
