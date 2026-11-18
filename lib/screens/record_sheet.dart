import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../format.dart';
import '../models/records.dart';
import '../services/review_prompt.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

/// Site, 昼/夜勤, 人工 and overtime for one entry of a worker on one day.
/// [recordId] null adds another entry for that day.
Future<void> showRecordSheet(
  BuildContext context, {
  required Worker worker,
  required DateTime day,
  String? recordId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordSheet(worker: worker, day: day, recordId: recordId),
  );
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({
    required this.worker,
    required this.day,
    required this.recordId,
  });

  final Worker worker;
  final DateTime day;
  final String? recordId;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  String? _siteId;
  double _units = 1;
  double _overtime = 0;
  double _hours = defaultWorkHours;
  Shift _shift = Shift.day;
  bool _ready = false;
  bool _existing = false;
  bool _showAllowance = false;
  final _allowanceYen = TextEditingController();
  final _allowanceMemo = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final controller = AppScope.of(context);
    final id = widget.recordId;
    final record = id == null ? null : controller.recordById(id);
    _existing = record != null;
    if (record != null) {
      _siteId = record.siteId;
      _units = record.units;
      _shift = record.shift;
      _overtime = record.overtimeHours;
      if (record.hours > 0) _hours = record.hours;
      if (record.allowance > 0 || record.allowanceMemo.isNotEmpty) {
        _showAllowance = true;
        _allowanceYen.text = '${record.allowance}';
        _allowanceMemo.text = record.allowanceMemo;
      }
    } else {
      // Another entry on a day that already has one: suggest the other half
      // of the day, the other shift and another 現場.
      final others = controller.recordsFor(widget.worker.id, widget.day);
      _siteId = controller.selectedSite?.id;
      if (others.isNotEmpty) {
        final total = others.fold<double>(0, (sum, r) => sum + r.units);
        _units = total < 1 ? 1 - total : 1;
        _shift = others.any((r) => r.shift == Shift.day)
            ? Shift.night
            : Shift.day;
        final used = {for (final r in others) r.siteId};
        for (final site in controller.sites) {
          if (!used.contains(site.id)) {
            _siteId = site.id;
            break;
          }
        }
      }
      if (widget.worker.payType != PayType.daily && _units > 1) _units = 1;
      _hours = _units * defaultWorkHours;
    }
    _ready = true;
  }

  @override
  void dispose() {
    _allowanceYen.dispose();
    _allowanceMemo.dispose();
    super.dispose();
  }

  int get _allowance {
    if (!_showAllowance) return 0;
    return parseYen(_allowanceYen.text) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final id = widget.recordId;
    final record = id == null ? null : controller.recordById(id);
    final base =
        record ??
        AppController.newRecord(widget.worker, dayKey(widget.day), '');
    final contractor = widget.worker.kind == WorkerKind.contractor;
    final payType = base.payType;
    final overtimeRate = base.overtimeRate;
    final selectedSite = [
      for (final s in controller.sites)
        if (s.id == _siteId) s,
    ].firstOrNull;
    final isArea = selectedSite?.isAreaSite == true;
    final wage = isArea
        ? 0
        : base
              .copyWith(units: _units, overtimeHours: _overtime, hours: _hours)
              .amount;
    final amount = wage + _allowance;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.worker.name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              '${formatJapaneseDate(widget.day)}${_existing ? '' : '　出面を追加'}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            const Text('現場', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final site in controller.sites)
                  ChoiceChip(
                    label: Text(site.isAreaSite ? '${site.name}（平米）' : site.name),
                    selected: site.id == _siteId,
                    onSelected: (_) => setState(() => _siteId = site.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('昼夜', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SegmentedButton<Shift>(
              key: const Key('record-shift'),
              segments: [
                for (final shift in Shift.values)
                  ButtonSegment(
                    value: shift,
                    label: Text(shift.label, key: Key('shift-${shift.key}')),
                  ),
              ],
              selected: {_shift},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _shift = value.first),
            ),
            const SizedBox(height: 16),
            Text(
              contractor && payType == PayType.daily ? '人工（入れた人数 × 日数）' : '人工',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            if (payType == PayType.daily) ...[
              Row(
                children: [
                  IconButton.outlined(
                    key: const Key('units-minus'),
                    onPressed: _units <= 0.5
                        ? null
                        : () => setState(() => _units -= 0.5),
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Text(
                      '${formatUnits(_units)}人工',
                      key: const Key('units-value'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    key: const Key('units-plus'),
                    onPressed: _units >= maxUnitsPerRecord
                        ? null
                        : () => setState(() => _units += 0.5),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final quick in const [0.5, 1.0, 2.0, 3.0, 5.0, 10.0])
                    ChoiceChip(
                      key: Key('units-$quick'),
                      label: Text(formatUnits(quick)),
                      selected: _units == quick,
                      onSelected: (_) => setState(() => _units = quick),
                    ),
                ],
              ),
            ] else
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('1人工（全日）')),
                  ButtonSegment(value: 0.5, label: Text('0.5人工（半日）')),
                ],
                selected: {_units},
                showSelectedIcon: false,
                onSelectionChanged: (value) => setState(() {
                  final next = value.first;
                  // Keep the hours in step with a full or half day unless
                  // the user changed them.
                  if (_hours == _units * defaultWorkHours) {
                    _hours = next * defaultWorkHours;
                  }
                  _units = next;
                }),
              ),
            if (payType == PayType.hourly) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '勤務時間',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton.outlined(
                    key: const Key('hours-minus'),
                    onPressed: _hours <= 0.5
                        ? null
                        : () => setState(() => _hours -= 0.5),
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      formatHours(_hours),
                      key: const Key('hours-value'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    key: const Key('hours-plus'),
                    onPressed: _hours >= 24
                        ? null
                        : () => setState(() => _hours += 0.5),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
            if (!isArea) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '残業',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.outlined(
                  key: const Key('overtime-minus'),
                  onPressed: _overtime <= 0
                      ? null
                      : () => setState(() => _overtime -= 0.5),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    formatHours(_overtime),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.outlined(
                  key: const Key('overtime-plus'),
                  onPressed: _overtime >= 12
                      ? null
                      : () => setState(() => _overtime += 0.5),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (overtimeRate == 0 && _overtime > 0)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '残業単価が0円のため、時間だけ記録します。単価は「名簿」で設定できます。',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
            if (!isArea) ...[
              const SizedBox(height: 14),
              Panel(
                color: AppColors.paper,
                child: Row(
                  children: [
                    Text(payType == PayType.monthly ? 'この日の残業代' : 'この日の金額'),
                    const Spacer(),
                    Text(
                      formatYen(amount),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              if (payType == PayType.monthly)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    '月給の職人は出勤だけを記録します。月給は集計で月に1回計上します。',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'この現場は平米割りです。日当は付きません。分けた金額は、現場の集計月に出ます。',
                  key: Key('area-site-note'),
                  style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                ),
              ),
            const SizedBox(height: 12),
            if (!_showAllowance)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('allowance-add'),
                  onPressed: () => setState(() => _showAllowance = true),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('＋色付け'),
                ),
              )
            else ...[
              const Text('色付け', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              TextField(
                key: const Key('allowance-yen'),
                controller: _allowanceYen,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '金額',
                  hintText: '例: 3000',
                  suffixText: '円',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('allowance-memo'),
                controller: _allowanceMemo,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'メモ（任意）',
                  hintText: '例: 搬入が大変だった',
                  counterText: '',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('allowance-clear'),
                  onPressed: () => setState(() {
                    _showAllowance = false;
                    _allowanceYen.clear();
                    _allowanceMemo.clear();
                  }),
                  child: const Text('色付けをやめる'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              key: const Key('save-record'),
              onPressed: _siteId == null
                  ? null
                  : () async {
                      final ok = await guard(
                        context,
                        () => controller.setRecord(
                          workerId: widget.worker.id,
                          recordId: widget.recordId,
                          shift: _shift,
                          day: widget.day,
                          siteId: _siteId!,
                          units: _units,
                          overtimeHours: isArea ? 0 : _overtime,
                          hours: payType == PayType.hourly ? _hours : null,
                          allowance: _allowance,
                          allowanceMemo: _showAllowance
                              ? _allowanceMemo.text
                              : '',
                        ),
                      );
                      if (ok) {
                        ReviewPrompt.afterEntry(controller.records.length);
                      }
                      if (ok && context.mounted) Navigator.pop(context);
                    },
              child: const Text('保存'),
            ),
            if (_existing)
              TextButton(
                key: const Key('clear-record'),
                onPressed: () async {
                  final ok = await guard(
                    context,
                    () => controller.clearRecordById(widget.recordId!),
                  );
                  if (ok && context.mounted) Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('この出面を消す'),
              ),
          ],
        ),
      ),
    );
  }
}
