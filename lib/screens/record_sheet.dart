import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../format.dart';
import '../models/records.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

/// Site, 人工 and overtime for one worker on one day.
Future<void> showRecordSheet(
  BuildContext context, {
  required Worker worker,
  required DateTime day,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordSheet(worker: worker, day: day),
  );
}

class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.worker, required this.day});

  final Worker worker;
  final DateTime day;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  String? _siteId;
  double _units = 1;
  double _overtime = 0;
  bool _ready = false;
  bool _existing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final controller = AppScope.of(context);
    final record = controller.recordFor(widget.worker.id, widget.day);
    _existing = record != null;
    _siteId = record?.siteId ?? controller.selectedSite?.id;
    _units = record?.units ?? 1;
    _overtime = record?.overtimeHours ?? 0;
    _ready = true;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final record = controller.recordFor(widget.worker.id, widget.day);
    final dayRate = record?.dayRate ?? widget.worker.dayRate;
    final overtimeRate = record?.overtimeRate ?? widget.worker.overtimeRate;
    final amount =
        (dayRate * _units).round() + (overtimeRate * _overtime).round();

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
              formatJapaneseDate(widget.day),
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
                    label: Text(site.name),
                    selected: site.id == _siteId,
                    onSelected: (_) => setState(() => _siteId = site.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('人工', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1人工（全日）')),
                ButtonSegment(value: 0.5, label: Text('0.5人工（半日）')),
              ],
              selected: {_units},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _units = value.first),
            ),
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
            const SizedBox(height: 14),
            Panel(
              color: AppColors.paper,
              child: Row(
                children: [
                  const Text('この日の金額'),
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
                          day: widget.day,
                          siteId: _siteId!,
                          units: _units,
                          overtimeHours: _overtime,
                        ),
                      );
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
                    () => controller.clearRecord(widget.worker.id, widget.day),
                  );
                  if (ok && context.mounted) Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('この日の出面を消す'),
              ),
          ],
        ),
      ),
    );
  }
}
