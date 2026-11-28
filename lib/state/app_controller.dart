import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';
import '../errors.dart';
import '../format.dart';
import '../ids.dart';
import '../logic/summary.dart';
import '../models/plans.dart';
import '../models/records.dart';
import '../services/plan_image.dart';
import '../plan/entitlement.dart';
import '../plan/trial_tip.dart';
import '../plan/limits.dart';
import '../services/pdf_report.dart';
import '../services/purchase_gateway.dart';

enum PurchasePhase { idle, pending, error }

enum RestoreResult { restored, nothingToRestore, failed }

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
  List<DayPlan> plans = [];
  Entitlement entitlement = const Entitlement();
  PurchasePhase purchasePhase = PurchasePhase.idle;
  String? purchaseError;
  List<StoreProduct> storeProducts = [];

  /// False until the App Store has answered once on the paywall.
  bool productsLoaded = false;
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

  /// True only when the App Store returned this product with its price.
  bool hasProduct(String productId) =>
      storeProducts.any((product) => product.id == productId);

  /// `1週間` when the App Store offers this Apple ID the free trial.
  String? trialFor(String productId) {
    for (final product in storeProducts) {
      if (product.id == productId) return product.trialLabel;
    }
    return null;
  }

  Future<void> load() async {
    await repository.init();
    workers = await repository.loadWorkers();
    sites = await repository.loadSites();
    records = await repository.loadRecords();
    plans = await repository.loadPlans();
    entitlement = await repository.loadEntitlement();
    final settings = await repository.loadSettings();
    final selected = settings['selectedSiteId'];
    _selectedSiteId = selected is String ? selected : null;
    final business = settings['businessName'];
    businessName = business is String ? business : '';
    trialTipShown = settings['trialTipShown'] == true;
    guideSeen = settings['guideSeen'] == true;
    if (!guideSeen && hasExistingData) {
      guideSeen = true;
      try {
        await _saveSettings();
      } catch (_) {
        // Existing users should never see the first-launch guide.
      }
    }
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
        : Entitlement(
            productId: active.productId,
            expiresAt: active.expiresAt,
            purchasedAt: active.purchasedAt,
          );
    await repository.saveEntitlement(entitlement);
  }

  Future<void> _saveSettings() {
    return repository.saveSettings({
      'selectedSiteId': ?_selectedSiteId,
      'businessName': businessName,
      if (trialTipShown) 'trialTipShown': true,
      if (guideSeen) 'guideSeen': true,
    });
  }

  /// The one-time tip for people in the free trial was already shown.
  bool trialTipShown = false;

  /// True once the first-launch guide was shown, skipped, or skipped because
  /// this is an existing user who already has data.
  bool guideSeen = false;

  bool get hasExistingData =>
      workers.isNotEmpty ||
      sites.isNotEmpty ||
      records.isNotEmpty ||
      plans.isNotEmpty;

  bool get shouldShowGuide => !guideSeen;

  Future<void> markGuideSeen() async {
    if (guideSeen) return;
    guideSeen = true;
    try {
      await _saveSettings();
    } catch (_) {
      // The guide is only a convenience; never block the app on it.
    }
  }

  bool get shouldShowTrialTip => TrialTip.shouldShow(
    entitlement: entitlement,
    now: _now(),
    alreadyShown: trialTipShown,
  );

  Future<void> markTrialTipShown() async {
    if (trialTipShown) return;
    trialTipShown = true;
    try {
      await _saveSettings();
    } catch (_) {
      // A missed save at worst shows the tip once more; never block the app.
    }
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

  /// The first entry of [workerId] on [day] (昼 before 夜勤), or null.
  DayRecord? recordFor(String workerId, DateTime day) {
    final all = recordsFor(workerId, day);
    return all.isEmpty ? null : all.first;
  }

  /// Every entry of [workerId] on [day]: 昼 before 夜勤, then in the order
  /// they were added.
  List<DayRecord> recordsFor(String workerId, DateTime day) {
    final key = dayKey(day);
    final found = [
      for (final r in records)
        if (r.workerId == workerId && r.day == key) r,
    ];
    // Stable: List.sort is not, so order by (shift, original index).
    final order = {for (var i = 0; i < found.length; i++) found[i].id: i};
    found.sort((a, b) {
      final byShift = a.shift.index.compareTo(b.shift.index);
      return byShift != 0 ? byShift : order[a.id]!.compareTo(order[b.id]!);
    });
    return found;
  }

  DayRecord? recordById(String id) {
    for (final r in records) {
      if (r.id == id) return r;
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
      final day = tryParseDayKey(r.day)?.day;
      if (day == null) continue;
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
    int dayRate = 0,
    int overtimeRate = 0,
    PayType payType = PayType.daily,
    int hourlyRate = 0,
    int monthlySalary = 0,
    WorkerKind kind = WorkerKind.employee,
  }) async {
    if (!canAddWorker) throw const LimitReached(LimitKind.workers);
    final worker = Worker(
      id: createId(),
      name: _requiredLine(
        name,
        kind == WorkerKind.contractor ? '会社名' : '名前',
        20,
      ),
      kind: kind,
      payType: payType,
      dayRate: _yen(dayRate, '日当'),
      hourlyRate: _yen(hourlyRate, '時給'),
      monthlySalary: _salary(monthlySalary),
      overtimeRate: _yen(overtimeRate, '残業単価'),
      createdAt: _now(),
    );
    final next = [...workers, worker];
    await repository.saveWorkers(next);
    workers = next;
    notifyListeners();
    return worker;
  }

  /// Rate changes apply to records from the first day of the current month,
  /// so months that were already closed keep the rate they were paid at.
  Future<void> updateWorker({
    required String id,
    required String name,
    int? dayRate,
    int overtimeRate = 0,
    PayType? payType,
    int? hourlyRate,
    int? monthlySalary,
    WorkerKind? kind,
  }) async {
    final index = workers.indexWhere((w) => w.id == id);
    if (index < 0) throw const InvalidInput('職人が見つかりません。');
    final current = workers[index];
    final updated = current.copyWith(
      name: _requiredLine(
        name,
        (kind ?? current.kind) == WorkerKind.contractor ? '会社名' : '名前',
        20,
      ),
      kind: kind,
      payType: payType,
      dayRate: _yen(dayRate ?? current.dayRate, '日当'),
      hourlyRate: _yen(hourlyRate ?? current.hourlyRate, '時給'),
      monthlySalary: _salary(monthlySalary ?? current.monthlySalary),
      overtimeRate: _yen(overtimeRate, '残業単価'),
    );
    workers = [...workers]..[index] = updated;
    final from = '${monthKey(_now())}-01';
    records = [
      for (final r in records)
        if (r.workerId == id && r.day.compareTo(from) >= 0)
          r.copyWith(
            payType: updated.payType,
            dayRate: updated.dayRate,
            hourlyRate: updated.hourlyRate,
            monthlySalary: updated.monthlySalary,
            overtimeRate: updated.overtimeRate,
            hours: updated.payType == PayType.hourly
                ? (r.hours > 0 ? r.hours : r.units * defaultWorkHours).clamp(
                    0.5,
                    24.0,
                  )
                : r.hours,
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
    plans = _plansWithout(workerId: id);
    await repository.saveWorkers(workers);
    await repository.saveRecords(records);
    await repository.savePlans(plans);
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

  Future<Site> addSite({
    required String name,
    String note = '',
    String address = '',
    bool isAreaSite = false,
    AreaAmountMode areaAmountMode = AreaAmountMode.areaTimesRate,
    double areaSqm = 0,
    int areaUnitPrice = 0,
    int contractAmount = 0,
    String settlementMonth = '',
  }) async {
    if (!canAddSite) throw const LimitReached(LimitKind.sites);
    final area = _areaFields(
      isAreaSite: isAreaSite,
      areaAmountMode: areaAmountMode,
      areaSqm: areaSqm,
      areaUnitPrice: areaUnitPrice,
      contractAmount: contractAmount,
      settlementMonth: settlementMonth,
    );
    final site = Site(
      id: createId(),
      name: _requiredLine(name, '現場名', 30),
      note: _optionalLine(note, 40),
      address: _optionalLine(address, maxSiteAddressLength),
      createdAt: _now(),
      isAreaSite: area.isAreaSite,
      areaAmountMode: area.areaAmountMode,
      areaSqm: area.areaSqm,
      areaUnitPrice: area.areaUnitPrice,
      contractAmount: area.contractAmount,
      settlementMonth: area.settlementMonth,
    );
    final next = [...sites, site];
    await repository.saveSites(next);
    sites = next;
    _selectedSiteId = site.id;
    await _saveSettings();
    notifyListeners();
    return site;
  }

  Future<void> updateSite({
    required String id,
    required String name,
    String note = '',
    String address = '',
    bool isAreaSite = false,
    AreaAmountMode areaAmountMode = AreaAmountMode.areaTimesRate,
    double areaSqm = 0,
    int areaUnitPrice = 0,
    int contractAmount = 0,
    String settlementMonth = '',
  }) async {
    final index = sites.indexWhere((s) => s.id == id);
    if (index < 0) throw const InvalidInput('現場が見つかりません。');
    final area = _areaFields(
      isAreaSite: isAreaSite,
      areaAmountMode: areaAmountMode,
      areaSqm: areaSqm,
      areaUnitPrice: areaUnitPrice,
      contractAmount: contractAmount,
      settlementMonth: settlementMonth,
    );
    sites = [...sites]
      ..[index] = sites[index].copyWith(
        name: _requiredLine(name, '現場名', 30),
        note: _optionalLine(note, 40),
        address: _optionalLine(address, maxSiteAddressLength),
        isAreaSite: area.isAreaSite,
        areaAmountMode: area.areaAmountMode,
        areaSqm: area.areaSqm,
        areaUnitPrice: area.areaUnitPrice,
        contractAmount: area.contractAmount,
        settlementMonth: area.settlementMonth,
      );
    await repository.saveSites(sites);
    notifyListeners();
  }

  Future<void> deleteSite(String id) async {
    sites = sites.where((s) => s.id != id).toList();
    records = records.where((r) => r.siteId != id).toList();
    plans = _plansWithout(siteId: id);
    if (_selectedSiteId == id) _selectedSiteId = null;
    await repository.saveSites(sites);
    await repository.saveRecords(records);
    await repository.savePlans(plans);
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

  /// One tap: none -> 1人工 -> 0.5人工 -> none, on the worker's first entry
  /// of the day. New entries go to the selected site. Returns that entry
  /// now, or null when it was removed.
  Future<DayRecord?> tapWorker(String workerId, DateTime day) async {
    final worker = workerById(workerId);
    if (worker == null) throw const InvalidInput('職人が見つかりません。');
    _ensureMonthOpen(day);
    final current = recordFor(workerId, day);
    DayRecord? next;
    if (current == null) {
      final site = selectedSite;
      if (site == null) throw const InvalidInput('先に現場を登録してください。');
      next = newRecord(worker, dayKey(day), site.id);
      await _replace(null, next);
    } else if (current.units > 0.5) {
      // Half day: an hourly worker's default 8h becomes 4h. Hours the user
      // typed in are kept. A crew of more than 1人工 goes back to 1人工.
      next = current.copyWith(
        units: current.units > 1 ? 1 : 0.5,
        hours: current.units > 1
            ? current.hours
            : current.hours == defaultWorkHours
            ? defaultWorkHours / 2
            : current.hours,
      );
      await _replace(current.id, next);
    } else {
      await _replace(current.id, null);
    }
    return next;
  }

  /// A full day (1人工) for [worker] with its current pay type and rates.
  static DayRecord newRecord(
    Worker worker,
    String day,
    String siteId, {
    double units = 1,
    Shift shift = Shift.day,
  }) {
    return DayRecord(
      shift: shift,
      workerId: worker.id,
      day: day,
      siteId: siteId,
      units: units,
      overtimeHours: 0,
      payType: worker.payType,
      hours: worker.payType == PayType.hourly ? units * defaultWorkHours : 0,
      dayRate: worker.dayRate,
      hourlyRate: worker.hourlyRate,
      monthlySalary: worker.monthlySalary,
      overtimeRate: worker.overtimeRate,
    );
  }

  /// Adds an entry ([recordId] null) or edits one. A worker can have several
  /// entries on a day, but not two for the same 現場 and 昼/夜勤.
  ///
  /// [units] is 0.5 or 1 for 時給 and 月給 workers, and any 0.1 step (min
  /// 0.1) up to [maxUnitsPerRecord] for 日当 (a 外注 crew). [hours] is the
  /// working time of an hourly worker (0.5〜24h). Other pay types ignore it.
  Future<void> setRecord({
    required String workerId,
    required DateTime day,
    required String siteId,
    required double units,
    required double overtimeHours,
    double? hours,
    String? recordId,
    Shift shift = Shift.day,
    int? allowance,
    String? allowanceMemo,
    int? transport,
    int? parking,
  }) async {
    final worker = workerById(workerId);
    if (worker == null) throw const InvalidInput('職人が見つかりません。');
    if (siteById(siteId) == null) throw const InvalidInput('現場が見つかりません。');
    _ensureMonthOpen(day);
    final existing = recordId == null ? null : recordById(recordId);
    if (recordId != null && existing == null) {
      throw const InvalidInput('出面が見つかりません。');
    }
    final base = existing ?? newRecord(worker, dayKey(day), siteId);
    _checkUnits(units, base.payType);
    if (overtimeHours < 0 || overtimeHours > 12) {
      throw const InvalidInput('残業は0〜12時間で入力してください。');
    }
    final key = dayKey(day);
    final clash = records.any(
      (r) =>
          r.id != existing?.id &&
          r.workerId == workerId &&
          r.day == key &&
          r.siteId == siteId &&
          r.shift == shift,
    );
    if (clash) {
      throw const InvalidInput('同じ現場・同じ昼夜の出面がすでにあります。そちらを編集してください。');
    }
    var workHours = 0.0;
    if (base.payType == PayType.hourly) {
      workHours = hours ?? units * defaultWorkHours;
      if (workHours < 0.5 || workHours > 24) {
        throw const InvalidInput('勤務時間は0.5〜24時間で入力してください。');
      }
    }
    final yen = allowance ?? base.allowance;
    if (yen < 0 || yen > 1000000) {
      throw const InvalidInput('色付けは0〜1,000,000円で入力してください。');
    }
    final travel = transport ?? base.transport;
    if (travel < 0 || travel > 1000000) {
      throw const InvalidInput('交通費は0〜1,000,000円で入力してください。');
    }
    final parkingYen = parking ?? base.parking;
    if (parkingYen < 0 || parkingYen > 1000000) {
      throw const InvalidInput('駐車場代は0〜1,000,000円で入力してください。');
    }
    await _replace(
      existing?.id,
      base.copyWith(
        siteId: siteId,
        units: roundUnits(units),
        overtimeHours: overtimeHours,
        hours: workHours,
        shift: shift,
        allowance: yen,
        allowanceMemo: _optionalLine(allowanceMemo ?? base.allowanceMemo, 40),
        transport: travel,
        parking: parkingYen,
      ),
    );
  }

  void _checkUnits(double units, PayType payType) {
    final rounded = roundUnits(units);
    if ((units - rounded).abs() > 1e-6) {
      if (payType != PayType.daily) {
        throw const InvalidInput('人工は1か0.5を選んでください。');
      }
      throw const InvalidInput('人工は0.1単位で入力してください。');
    }
    if (payType != PayType.daily) {
      if (rounded != 1 && rounded != 0.5) {
        throw const InvalidInput('人工は1か0.5を選んでください。');
      }
      return;
    }
    if (rounded < dailyUnitStep) {
      throw const InvalidInput('人工は0.1単位で入力してください。');
    }
    if (rounded > maxUnitsPerRecord) {
      throw InvalidInput('人工は${formatUnits(maxUnitsPerRecord)}までです。');
    }
  }

  /// Removes every entry of [workerId] on [day].
  Future<void> clearRecord(String workerId, DateTime day) async {
    final key = dayKey(day);
    await _commit([
      for (final r in records)
        if (!(r.workerId == workerId && r.day == key)) r,
    ]);
  }

  /// Removes one entry.
  Future<void> clearRecordById(String id) async {
    await _replace(id, null);
  }

  /// Marks every 従業員 without an entry as 1人工 at the selected site.
  /// 外注 are left out (they need a crew size). Returns how many were added.
  Future<int> markAll(DateTime day) async {
    _ensureMonthOpen(day);
    final site = selectedSite;
    if (site == null) throw const InvalidInput('先に現場を登録してください。');
    final key = dayKey(day);
    final added = <DayRecord>[];
    for (final w in workers) {
      if (w.kind == WorkerKind.contractor) continue;
      if (recordFor(w.id, day) != null) continue;
      added.add(newRecord(w, key, site.id));
    }
    if (added.isEmpty) return 0;
    records = [...records, ...added];
    await repository.saveRecords(records);
    notifyListeners();
    return added.length;
  }

  /// Replaces the entry with [id] by [next], removes it when [next] is null,
  /// or adds [next] when [id] is null.
  Future<void> _replace(String? id, DayRecord? next) {
    return _commit([
      for (final r in records)
        if (r.id == id) ...[?next] else r,
      if (id == null) ?next,
    ]);
  }

  Future<void> _commit(List<DayRecord> updated) async {
    final previous = records;
    records = updated;
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

  // ---------------------------------------------------------------- plans

  DayPlan planFor(DateTime day) {
    final key = dayKey(day);
    for (final plan in plans) {
      if (plan.day == key) return plan;
    }
    return DayPlan(day: key);
  }

  /// Inserts or replaces the plan for [plan.day], drops empty site rows,
  /// and forgets plans outside the retention window.
  Future<void> savePlan(DayPlan plan) async {
    if (tryParseDayKey(plan.day) == null) {
      throw const InvalidInput('日付の形式が不正です。');
    }
    final cleaned = DayPlan(
      day: plan.day,
      sites: [
        for (final s in plan.sites)
          if (s.siteId.isNotEmpty && siteById(s.siteId) != null)
            SitePlan(
              siteId: s.siteId,
              workerIds: [
                for (final id in s.workerIds)
                  if (workerById(id) != null) id,
              ],
              note: _optionalLine(s.note, maxPlanNoteLength),
            ),
      ],
    );
    final next = [
      for (final p in plans)
        if (p.day != cleaned.day) p,
      if (!cleaned.isEmpty) cleaned,
    ];
    plans = _prunePlans(next);
    notifyListeners();
    await repository.savePlans(plans);
  }

  Future<void> clearPlan(DateTime day) async {
    final key = dayKey(day);
    plans = [
      for (final p in plans)
        if (p.day != key) p,
    ];
    await repository.savePlans(plans);
    notifyListeners();
  }

  /// Assigns [workerId] to [siteId] on [day], or removes them if they
  /// were already there. A worker is only on one site per day.
  Future<void> togglePlanWorker({
    required DateTime day,
    required String siteId,
    required String workerId,
  }) async {
    if (siteById(siteId) == null) {
      throw const InvalidInput('現場が見つかりません。');
    }
    if (workerById(workerId) == null) {
      throw const InvalidInput('職人が見つかりません。');
    }
    final current = planFor(day);
    final already = current.site(siteId).workerIds.contains(workerId);
    final sites = <SitePlan>[
      for (final s in current.sites)
        if (s.siteId != siteId)
          s.copyWith(
            workerIds: [
              for (final id in s.workerIds)
                if (id != workerId) id,
            ],
          ),
    ];
    final mine = current.site(siteId);
    final workers = [
      for (final id in mine.workerIds)
        if (id != workerId) id,
      if (!already) workerId,
    ];
    sites.add(mine.copyWith(workerIds: workers));
    await savePlan(current.copyWith(sites: sites));
  }

  Future<void> setPlanNote({
    required DateTime day,
    required String siteId,
    required String note,
  }) async {
    if (siteById(siteId) == null) {
      throw const InvalidInput('現場が見つかりません。');
    }
    final current = planFor(day);
    final sites = [
      for (final s in current.sites)
        if (s.siteId != siteId) s,
      current.site(siteId).copyWith(note: note),
    ];
    await savePlan(current.copyWith(sites: sites));
  }

  /// Adds a 1人工 出面 for each planned worker who does not yet have an
  /// entry that day. Existing 出面 are left unchanged. Follows the usual
  /// month lock (free users: this month only).
  Future<int> applyPlanAsAttendance(DateTime day) async {
    _ensureMonthOpen(day);
    final plan = planFor(day);
    if (plan.isEmpty) throw const InvalidInput('予定がまだありません。');
    var added = 0;
    for (final site in plan.sites) {
      if (siteById(site.siteId) == null) continue;
      for (final workerId in site.workerIds) {
        final worker = workerById(workerId);
        if (worker == null) continue;
        if (recordsFor(workerId, day).isNotEmpty) continue;
        await setRecord(
          workerId: workerId,
          day: day,
          siteId: site.siteId,
          units: 1,
          overtimeHours: 0,
        );
        added++;
      }
    }
    return added;
  }

  Future<Uint8List> planImageBytes(DateTime day) async {
    final plan = planFor(day);
    if (plan.isEmpty) throw const InvalidInput('予定がまだありません。');
    final content = planImageContent(
      plan: plan,
      day: DateTime(day.year, day.month, day.day),
      sites: sites,
      workers: workers,
      businessName: businessName,
    );
    if (content.isEmpty) throw const InvalidInput('予定がまだありません。');
    return renderPlanPng(content: content, fontData: await _fontData());
  }

  Future<String> exportPlanImage(DateTime day) async {
    final bytes = await planImageBytes(day);
    return repository.writeExport(planFileName(day), bytes);
  }

  List<DayPlan> _plansWithout({String? workerId, String? siteId}) {
    return [
      for (final plan in plans)
        DayPlan(
          day: plan.day,
          sites: [
            for (final s in plan.sites)
              if (siteId == null || s.siteId != siteId)
                s.copyWith(
                  workerIds: [
                    for (final id in s.workerIds)
                      if (id != workerId) id,
                  ],
                ),
          ],
        ),
    ];
  }

  List<DayPlan> _prunePlans(List<DayPlan> input) {
    final today = DateTime(_now().year, _now().month, _now().day);
    final start = today.subtract(const Duration(days: planRetentionDays));
    final end = DateTime(
      today.year,
      today.month,
      today.day + planRetentionDays,
    );
    return [
      for (final plan in input)
        if (!plan.isEmpty)
          if (_inWindow(plan.day, start, end)) plan,
    ];
  }

  bool _inWindow(String key, DateTime start, DateTime end) {
    final day = tryParseDayKey(key);
    if (day == null) return false;
    return !day.isBefore(start) && !day.isAfter(end);
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

  /// Personal 出面 PDF for [workerId] only. Sharing the file is premium.
  Future<Uint8List> pdfBytesForWorker(DateTime month, String workerId) async {
    if (!canOpenMonth(month)) throw const LimitReached(LimitKind.history);
    final summary = summaryFor(month);
    final worker = summary.workers.where((w) => w.worker.id == workerId);
    if (worker.isEmpty) {
      throw const InvalidInput('この月の出面がありません。');
    }
    return buildWorkerMonthlyPdf(
      fontData: await _fontData(),
      summary: summary,
      worker: worker.first,
      title: businessName,
    );
  }

  Future<String> exportWorkerPdf(DateTime month, String workerId) async {
    if (!premium) throw const LimitReached(LimitKind.export);
    final bytes = await pdfBytesForWorker(month, workerId);
    final name = workerById(workerId)?.name ?? '職人';
    return repository.writeExport(
      exportWorkerFileName(month, name, 'pdf'),
      bytes,
    );
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
    productsLoaded = true;
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

  Future<RestoreResult> restorePremium() async {
    if (purchasePhase == PurchasePhase.pending) {
      return RestoreResult.failed;
    }
    purchasePhase = PurchasePhase.pending;
    purchaseError = null;
    notifyListeners();
    final already = premium;
    try {
      await purchases.restore();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (premium) {
        purchasePhase = PurchasePhase.idle;
        purchaseError = null;
        notifyListeners();
        return RestoreResult.restored;
      }
      if (purchasePhase == PurchasePhase.error) {
        notifyListeners();
        return RestoreResult.failed;
      }
      if (!already) {
        purchasePhase = PurchasePhase.error;
        purchaseError = '復元できる契約は見つかりませんでした。契約したApple IDでサインインしているか確認してください。';
        notifyListeners();
        return RestoreResult.nothingToRestore;
      }
      purchasePhase = PurchasePhase.idle;
      notifyListeners();
      return RestoreResult.nothingToRestore;
    } on StoreUnavailable catch (error) {
      purchasePhase = PurchasePhase.error;
      purchaseError = error.message;
      notifyListeners();
      return RestoreResult.failed;
    } catch (_) {
      purchasePhase = PurchasePhase.error;
      purchaseError = '復元できませんでした。通信状況を確認してください。';
      notifyListeners();
      return RestoreResult.failed;
    }
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

  int _salary(int value) {
    if (value < 0 || value > 10000000) {
      throw const InvalidInput('月給は0〜10,000,000円で入力してください。');
    }
    return value;
  }

  int _yen(int value, String label) {
    if (value < 0 || value > 1000000) {
      throw InvalidInput('$labelは0〜1,000,000円で入力してください。');
    }
    return value;
  }

  static final _monthKeyPattern = RegExp(r'^\d{4}-\d{2}$');

  /// Validates 平米の現場 fields. When the switch is off, values are kept
  /// so the user can turn it back on without typing them again, but they
  /// have no effect on pay.
  ({
    bool isAreaSite,
    AreaAmountMode areaAmountMode,
    double areaSqm,
    int areaUnitPrice,
    int contractAmount,
    String settlementMonth,
  })
  _areaFields({
    required bool isAreaSite,
    required AreaAmountMode areaAmountMode,
    required double areaSqm,
    required int areaUnitPrice,
    required int contractAmount,
    required String settlementMonth,
  }) {
    final month = settlementMonth.trim();
    if (!isAreaSite) {
      return (
        isAreaSite: false,
        areaAmountMode: areaAmountMode,
        areaSqm: areaSqm,
        areaUnitPrice: areaUnitPrice,
        contractAmount: contractAmount,
        settlementMonth: month,
      );
    }
    if (!_monthKeyPattern.hasMatch(month)) {
      throw const InvalidInput('集計月を選んでください。');
    }
    if (areaAmountMode == AreaAmountMode.contract) {
      if (contractAmount <= 0 || contractAmount > 100000000) {
        throw const InvalidInput('請負額は1〜100,000,000円で入力してください。');
      }
    } else {
      if (areaSqm <= 0 || areaSqm > 100000) {
        throw const InvalidInput('平米数を入力してください。');
      }
      if (areaUnitPrice <= 0 || areaUnitPrice > 10000000) {
        throw const InvalidInput('平米単価は1〜10,000,000円で入力してください。');
      }
    }
    return (
      isAreaSite: true,
      areaAmountMode: areaAmountMode,
      areaSqm: areaSqm,
      areaUnitPrice: areaUnitPrice,
      contractAmount: contractAmount,
      settlementMonth: month,
    );
  }

  @override
  void dispose() {
    purchases.dispose();
    super.dispose();
  }
}
