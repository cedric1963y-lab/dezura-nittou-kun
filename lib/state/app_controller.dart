import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../errors.dart';
import '../format.dart';
import '../ids.dart';
import '../logic/summary.dart';
import '../models/records.dart';
import '../plan/entitlement.dart';
import '../plan/limits.dart';
import '../services/pdf_report.dart';
import '../services/purchase_gateway.dart';

enum PurchasePhase { idle, pending, error }

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.purchases,
    Future<ByteData> Function()? loadFont,
    DateTime Function()? now,
    this.demoPremium = false,
  }) : _loadFont = loadFont ?? _loadBundledFont,
       _now = now ?? DateTime.now;

  final Repository repository;
  final PurchaseGateway purchases;
  final Future<ByteData> Function() _loadFont;
  final DateTime Function() _now;

  /// Debug builds only: shows the premium state for store screenshots.
  final bool demoPremium;

  List<Worker> workers = [];
  List<Site> sites = [];
  List<DayRecord> records = [];
  Entitlement entitlement = const Entitlement();
  PurchasePhase purchasePhase = PurchasePhase.idle;
  String? purchaseError;
  List<StoreProduct> storeProducts = [];
  String? _selectedSiteId;
  String businessName = '';
  ByteData? _font;

  DateTime get now => _now();

  bool get premium => demoPremium || entitlement.isActiveAt(_now());

  bool get canAddWorker =>
      PlanLimits.canAddWorker(premium: premium, workerCount: workers.length);

  bool get canAddSite =>
      PlanLimits.canAddSite(premium: premium, siteCount: sites.length);

  bool canOpenMonth(DateTime month) =>
      PlanLimits.canOpenMonth(premium: premium, month: month, now: _now());

  String priceFor(String productId) {
    for (final product in storeProducts) {
      if (product.id == productId) return product.priceLabel;
    }
    return PlanLimits.priceLabelFor(productId);
  }

  Future<void> load() async {
    await repository.init();
    workers = await repository.loadWorkers();
    sites = await repository.loadSites();
    records = await repository.loadRecords();
    entitlement = await repository.loadEntitlement();
    final settings = await repository.loadSettings();
    final selected = settings['selectedSiteId'];
    _selectedSiteId = selected is String ? selected : null;
    final business = settings['businessName'];
    businessName = business is String ? business : '';
    try {
      await purchases.start(_onPurchase);
      await _applyStoreSubscriptions();
    } catch (_) {
      // Records still work when StoreKit cannot start.
    }
    notifyListeners();
  }

  Future<void> _applyStoreSubscriptions() async {
    final found = await purchases.currentSubscriptions();
    if (found == null) return;
    final active = activeSubscription(found, _now());
    entitlement = active == null
        ? const Entitlement()
        : Entitlement(productId: active.productId, expiresAt: active.expiresAt);
    await repository.saveEntitlement(entitlement);
  }

  Future<void> _saveSettings() {
    return repository.saveSettings({
      'selectedSiteId': ?_selectedSiteId,
      'businessName': businessName,
    });
  }

  // ---------------------------------------------------------------- lookups

  Worker? workerById(String id) {
    for (final w in workers) {
      if (w.id == id) return w;
    }
    return null;
  }

  Site? siteById(String id) {
    for (final s in sites) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The site new taps go to. Falls back to the first site.
  Site? get selectedSite {
    final id = _selectedSiteId;
    if (id != null) {
      final site = siteById(id);
      if (site != null) return site;
    }
    return sites.isEmpty ? null : sites.first;
  }

  DayRecord? recordFor(String workerId, DateTime day) {
    final key = dayKey(day);
    for (final r in records) {
      if (r.workerId == workerId && r.day == key) return r;
    }
    return null;
  }

  List<DayRecord> recordsOn(DateTime day) {
    final key = dayKey(day);
    return records.where((r) => r.day == key).toList();
  }

  /// 人工 per day of [month], for the calendar badges.
  Map<int, double> unitsByDay(DateTime month) {
    final prefix = '${monthKey(month)}-';
    final known = {for (final w in workers) w.id};
    final result = <int, double>{};
    for (final r in records) {
      if (!r.day.startsWith(prefix) || !known.contains(r.workerId)) continue;
      final day = parseDayKey(r.day).day;
      result[day] = (result[day] ?? 0) + r.units;
    }
    return result;
  }

  int recordCountForWorker(String id) =>
      records.where((r) => r.workerId == id).length;

  int recordCountForSite(String id) =>
      records.where((r) => r.siteId == id).length;

  // ---------------------------------------------------------------- workers

  Future<Worker> addWorker({
    required String name,
    required int dayRate,
    int overtimeRate = 0,
  }) async {
    if (!canAddWorker) throw const LimitReached(LimitKind.workers);
    final worker = Worker(
      id: createId(),
      name: _requiredLine(name, '名前', 20),
      dayRate: _yen(dayRate, '日当'),
      overtimeRate: _yen(overtimeRate, '残業単価'),
      createdAt: _now(),
    );
    workers = [...workers, worker];
    await repository.saveWorkers(workers);
    notifyListeners();
    return worker;
  }

  /// Rate changes apply to records from the first day of the current month,
  /// so months that were already closed keep the rate they were paid at.
  Future<void> updateWorker({
    required String id,
    required String name,
    required int dayRate,
    int overtimeRate = 0,
  }) async {
    final index = workers.indexWhere((w) => w.id == id);
    if (index < 0) throw const InvalidInput('職人が見つかりません。');
    final updated = workers[index].copyWith(
      name: _requiredLine(name, '名前', 20),
      dayRate: _yen(dayRate, '日当'),
      overtimeRate: _yen(overtimeRate, '残業単価'),
    );
    workers = [...workers]..[index] = updated;
    final from = '${monthKey(_now())}-01';
    records = [
      for (final r in records)
        if (r.workerId == id && r.day.compareTo(from) >= 0)
          r.copyWith(
            dayRate: updated.dayRate,
            overtimeRate: updated.overtimeRate,
          )
        else
          r,
    ];
    await repository.saveWorkers(workers);
    await repository.saveRecords(records);
    notifyListeners();
  }

  Future<void> deleteWorker(String id) async {
    workers = workers.where((w) => w.id != id).toList();
    records = records.where((r) => r.workerId != id).toList();
    await repository.saveWorkers(workers);
    await repository.saveRecords(records);
    notifyListeners();
  }

  Future<void> moveWorker(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= workers.length) return;
    final list = [...workers];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    workers = list;
    await repository.saveWorkers(workers);
    notifyListeners();
  }

  // ------------------------------------------------------------------ sites

  Future<Site> addSite({required String name, String note = ''}) async {
    if (!canAddSite) throw const LimitReached(LimitKind.sites);
    final site = Site(
      id: createId(),
      name: _requiredLine(name, '現場名', 30),
      note: _optionalLine(note, 40),
      createdAt: _now(),
    );
    sites = [...sites, site];
    _selectedSiteId = site.id;
    await repository.saveSites(sites);
    await _saveSettings();
    notifyListeners();
    return site;
  }

  Future<void> updateSite({
    required String id,
    required String name,
    String note = '',
  }) async {
    final index = sites.indexWhere((s) => s.id == id);
    if (index < 0) throw const InvalidInput('現場が見つかりません。');
    sites = [...sites]
      ..[index] = sites[index].copyWith(
        name: _requiredLine(name, '現場名', 30),
        note: _optionalLine(note, 40),
      );
    await repository.saveSites(sites);
    notifyListeners();
  }

  Future<void> deleteSite(String id) async {
    sites = sites.where((s) => s.id != id).toList();
    records = records.where((r) => r.siteId != id).toList();
    if (_selectedSiteId == id) _selectedSiteId = null;
    await repository.saveSites(sites);
    await repository.saveRecords(records);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> selectSite(String id) async {
    if (siteById(id) == null) return;
    _selectedSiteId = id;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setBusinessName(String value) async {
    businessName = _optionalLine(value, 30);
    await _saveSettings();
    notifyListeners();
  }

  // ---------------------------------------------------------------- records

  /// One tap: none -> 1人工 -> 0.5人工 -> none. New records go to the
  /// selected site. Returns the record now on that day, or null.
  Future<DayRecord?> tapWorker(String workerId, DateTime day) async {
    final worker = workerById(workerId);
    if (worker == null) throw const InvalidInput('職人が見つかりません。');
    _ensureMonthOpen(day);
    final current = recordFor(workerId, day);
    DayRecord? next;
    if (current == null) {
      final site = selectedSite;
      if (site == null) throw const InvalidInput('先に現場を登録してください。');
      next = DayRecord(
        workerId: workerId,
        day: dayKey(day),
        siteId: site.id,
        units: 1,
        overtimeHours: 0,
        dayRate: worker.dayRate,
        overtimeRate: worker.overtimeRate,
      );
    } else if (current.units >= 1) {
      next = current.copyWith(units: 0.5);
    } else {
      next = null;
    }
    await _replace(workerId, day, next);
    return next;
  }

  Future<void> setRecord({
    required String workerId,
    required DateTime day,
    required String siteId,
    required double units,
    required double overtimeHours,
  }) async {
    final worker = workerById(workerId);
    if (worker == null) throw const InvalidInput('職人が見つかりません。');
    if (siteById(siteId) == null) throw const InvalidInput('現場が見つかりません。');
    _ensureMonthOpen(day);
    if (units != 1 && units != 0.5) {
      throw const InvalidInput('人工は1か0.5を選んでください。');
    }
    if (overtimeHours < 0 || overtimeHours > 12) {
      throw const InvalidInput('残業は0〜12時間で入力してください。');
    }
    final existing = recordFor(workerId, day);
    await _replace(
      workerId,
      day,
      DayRecord(
        workerId: workerId,
        day: dayKey(day),
        siteId: siteId,
        units: units,
        overtimeHours: overtimeHours,
        dayRate: existing?.dayRate ?? worker.dayRate,
        overtimeRate: existing?.overtimeRate ?? worker.overtimeRate,
      ),
    );
  }

  Future<void> clearRecord(String workerId, DateTime day) async {
    await _replace(workerId, day, null);
  }

  /// Marks every worker without a record as 1人工 at the selected site.
  /// Returns how many were added.
  Future<int> markAll(DateTime day) async {
    _ensureMonthOpen(day);
    final site = selectedSite;
    if (site == null) throw const InvalidInput('先に現場を登録してください。');
    final key = dayKey(day);
    final added = <DayRecord>[];
    for (final w in workers) {
      if (recordFor(w.id, day) != null) continue;
      added.add(
        DayRecord(
          workerId: w.id,
          day: key,
          siteId: site.id,
          units: 1,
          overtimeHours: 0,
          dayRate: w.dayRate,
          overtimeRate: w.overtimeRate,
        ),
      );
    }
    if (added.isEmpty) return 0;
    records = [...records, ...added];
    await repository.saveRecords(records);
    notifyListeners();
    return added.length;
  }

  Future<void> _replace(String workerId, DateTime day, DayRecord? next) async {
    final key = dayKey(day);
    final previous = records;
    records = [
      for (final r in records)
        if (!(r.workerId == workerId && r.day == key)) r,
      ?next,
    ];
    notifyListeners();
    try {
      await repository.saveRecords(records);
    } catch (_) {
      records = previous;
      notifyListeners();
      rethrow;
    }
  }

  void _ensureMonthOpen(DateTime day) {
    if (!canOpenMonth(day)) throw const LimitReached(LimitKind.history);
  }

  // ---------------------------------------------------------------- summary

  MonthSummary summaryFor(DateTime month) => summarizeMonth(
    month: month,
    workers: workers,
    sites: sites,
    records: records,
  );

  String textFor(DateTime month) {
    if (!canOpenMonth(month)) throw const LimitReached(LimitKind.history);
    return summaryAsText(summaryFor(month));
  }

  /// PDF bytes for the in-app preview. Sharing the file is premium.
  Future<Uint8List> pdfBytesFor(DateTime month) async {
    if (!canOpenMonth(month)) throw const LimitReached(LimitKind.history);
    return buildMonthlyPdf(
      fontData: await _fontData(),
      summary: summaryFor(month),
      title: businessName,
    );
  }

  Future<String> exportPdf(DateTime month) async {
    if (!premium) throw const LimitReached(LimitKind.export);
    final bytes = await pdfBytesFor(month);
    return repository.writeExport(exportFileName(month, 'pdf'), bytes);
  }

  Future<String> exportCsv(DateTime month) async {
    if (!premium) throw const LimitReached(LimitKind.export);
    if (!canOpenMonth(month)) throw const LimitReached(LimitKind.history);
    final csv = summaryAsCsv(summaryFor(month));
    return repository.writeExport(
      exportFileName(month, 'csv'),
      Uint8List.fromList(utf8.encode(csv)),
    );
  }

  // -------------------------------------------------------------- purchases

  Future<void> refreshProduct() async {
    try {
      storeProducts = await purchases.loadProducts();
    } catch (_) {
      storeProducts = [];
    }
    notifyListeners();
  }

  Future<void> buyPlan(String productId) async {
    if (purchasePhase == PurchasePhase.pending) return;
    if (!PlanLimits.isPremiumProduct(productId)) return;
    if (entitlement.isActiveAt(_now()) && entitlement.productId == productId) {
      return;
    }
    purchasePhase = PurchasePhase.pending;
    purchaseError = null;
    notifyListeners();
    try {
      await purchases.buy(productId);
    } on StoreUnavailable catch (error) {
      purchasePhase = PurchasePhase.error;
      purchaseError = error.message;
      notifyListeners();
    } catch (_) {
      purchasePhase = PurchasePhase.error;
      purchaseError = '購入を開始できませんでした。通信状況を確認してください。';
      notifyListeners();
    }
  }

  Future<void> restorePremium() async {
    if (purchasePhase == PurchasePhase.pending) return;
    purchasePhase = PurchasePhase.pending;
    purchaseError = null;
    notifyListeners();
    final already = premium;
    try {
      await purchases.restore();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (purchasePhase == PurchasePhase.pending && !premium && !already) {
        purchasePhase = PurchasePhase.error;
        purchaseError = '復元できる契約は見つかりませんでした。契約したApple IDでサインインしているか確認してください。';
      } else if (purchasePhase == PurchasePhase.pending) {
        purchasePhase = PurchasePhase.idle;
      }
    } on StoreUnavailable catch (error) {
      purchasePhase = PurchasePhase.error;
      purchaseError = error.message;
    } catch (_) {
      purchasePhase = PurchasePhase.error;
      purchaseError = '復元できませんでした。通信状況を確認してください。';
    }
    notifyListeners();
  }

  Future<void> _onPurchase(PurchaseEvent event) async {
    switch (event.kind) {
      case PurchaseEventKind.unlocked:
        final productId = event.productId;
        final expiresAt = event.expiresAt;
        if (productId == null ||
            expiresAt == null ||
            !PlanLimits.isPremiumProduct(productId) ||
            !expiresAt.isAfter(_now())) {
          purchasePhase = PurchasePhase.error;
          purchaseError = '有効な契約は見つかりませんでした。期限が切れている場合は、月額または年額を開始してください。';
          break;
        }
        entitlement = Entitlement(productId: productId, expiresAt: expiresAt);
        purchasePhase = PurchasePhase.idle;
        purchaseError = null;
        try {
          await repository.saveEntitlement(entitlement);
        } catch (_) {
          purchasePhase = PurchasePhase.error;
          purchaseError = '契約は確認できましたが、端末への保存に失敗しました。この画面を開いたまま、もう一度お試しください。';
        }
      case PurchaseEventKind.pending:
        purchasePhase = PurchasePhase.pending;
        purchaseError = null;
      case PurchaseEventKind.canceled:
        if (purchasePhase == PurchasePhase.pending) {
          purchasePhase = PurchasePhase.idle;
        }
      case PurchaseEventKind.error:
        purchasePhase = PurchasePhase.error;
        purchaseError = event.message ?? '購入できませんでした。';
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers

  Future<ByteData> _fontData() async => _font ??= await _loadFont();

  static Future<ByteData> _loadBundledFont() {
    return rootBundle.load('assets/fonts/NotoSansJP-Regular.ttf');
  }

  String _requiredLine(String input, String label, int max) {
    final text = collapseWhitespace(input);
    if (text.isEmpty) throw InvalidInput('$labelを入力してください。');
    if (text.length > max) throw InvalidInput('$labelは$max文字までです。');
    return text;
  }

  String _optionalLine(String input, int max) {
    final text = collapseWhitespace(input);
    if (text.length > max) throw InvalidInput('$max文字までにしてください。');
    return text;
  }

  int _yen(int value, String label) {
    if (value < 0 || value > 1000000) {
      throw InvalidInput('$labelは0〜1,000,000円で入力してください。');
    }
    return value;
  }

  @override
  void dispose() {
    purchases.dispose();
    super.dispose();
  }
}
