import 'package:flutter/material.dart';

import '../errors.dart';
import '../format.dart';
import '../models/records.dart';
import '../screens/premium_screen.dart';
import '../services/links.dart';
import '../theme.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> openPremium(BuildContext context, {LimitKind? reason}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PremiumScreen(reason: reason)),
  );
}

/// Runs [action] and turns known failures into a snack bar or the premium
/// screen. Returns false when the action failed.
Future<bool> guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on LimitReached catch (error) {
    if (context.mounted) await openPremium(context, reason: error.kind);
  } on InvalidInput catch (error) {
    if (context.mounted) showSnack(context, error.message);
  } catch (_) {
    if (context.mounted) {
      showSnack(context, '保存できませんでした。iPhoneの空き容量を確認してください。');
    }
  }
  return false;
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmLabel,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

class WorkerDraft {
  const WorkerDraft({
    required this.name,
    required this.dayRate,
    required this.overtimeRate,
    this.payType = PayType.daily,
    this.hourlyRate = 0,
    this.monthlySalary = 0,
    this.kind = WorkerKind.employee,
  });

  final String name;
  final WorkerKind kind;
  final PayType payType;
  final int dayRate;
  final int hourlyRate;
  final int monthlySalary;
  final int overtimeRate;
}

Future<WorkerDraft?> showWorkerDialog(
  BuildContext context, {
  String title = '職人・外注を追加',
  String saveLabel = '追加',
  String initialName = '',
  int? initialDayRate,
  int initialOvertimeRate = 0,
  PayType initialPayType = PayType.daily,
  int initialHourlyRate = 0,
  int initialMonthlySalary = 0,
  WorkerKind initialKind = WorkerKind.employee,
  String? note,
}) {
  return showDialog<WorkerDraft>(
    context: context,
    builder: (context) => _WorkerDialog(
      title: title,
      saveLabel: saveLabel,
      initialName: initialName,
      initialRates: {
        PayType.daily: initialDayRate,
        PayType.hourly: initialHourlyRate == 0 ? null : initialHourlyRate,
        PayType.monthly: initialMonthlySalary == 0
            ? null
            : initialMonthlySalary,
      },
      initialPayType: initialPayType,
      initialKind: initialKind,
      initialOvertimeRate: initialOvertimeRate,
      note: note,
    ),
  );
}

class _WorkerDialog extends StatefulWidget {
  const _WorkerDialog({
    required this.title,
    required this.saveLabel,
    required this.initialName,
    required this.initialRates,
    required this.initialPayType,
    required this.initialKind,
    required this.initialOvertimeRate,
    required this.note,
  });

  final String title;
  final String saveLabel;
  final String initialName;
  final Map<PayType, int?> initialRates;
  final PayType initialPayType;
  final WorkerKind initialKind;
  final int initialOvertimeRate;
  final String? note;

  @override
  State<_WorkerDialog> createState() => _WorkerDialogState();
}

class _WorkerDialogState extends State<_WorkerDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _rates = {
    for (final type in PayType.values)
      type: TextEditingController(
        text: widget.initialRates[type]?.toString() ?? '',
      ),
  };
  late final _overtime = TextEditingController(
    text: widget.initialOvertimeRate == 0
        ? ''
        : widget.initialOvertimeRate.toString(),
  );
  late PayType _payType = widget.initialPayType;
  late WorkerKind _kind = widget.initialKind;
  String? _error;

  bool get _contractor => _kind == WorkerKind.contractor;

  static const _rateLabels = {
    PayType.daily: '日当（1人工あたり）',
    PayType.hourly: '時給（1時間あたり）',
    PayType.monthly: '月給（1か月あたり）',
  };
  static const _rateHints = {
    PayType.daily: '例: 18000',
    PayType.hourly: '例: 1500',
    PayType.monthly: '例: 300000',
  };

  @override
  void dispose() {
    _name.dispose();
    for (final c in _rates.values) {
      c.dispose();
    }
    _overtime.dispose();
    super.dispose();
  }

  int _rateOf(PayType type) =>
      parseYen(_rates[type]!.text) ?? widget.initialRates[type] ?? 0;

  void _save() {
    final name = _name.text.trim();
    final rate = parseYen(_rates[_payType]!.text);
    final overtime = parseYen(_overtime.text) ?? 0;
    if (name.isEmpty) {
      setState(() => _error = _contractor ? '会社名を入力してください。' : '名前を入力してください。');
      return;
    }
    if (rate == null) {
      setState(() => _error = '${_payType.label}を数字で入力してください。');
      return;
    }
    Navigator.pop(
      context,
      WorkerDraft(
        name: name,
        kind: _kind,
        payType: _payType,
        dayRate: _payType == PayType.daily ? rate : _rateOf(PayType.daily),
        hourlyRate: _payType == PayType.hourly ? rate : _rateOf(PayType.hourly),
        monthlySalary: _payType == PayType.monthly
            ? rate
            : _rateOf(PayType.monthly),
        overtimeRate: overtime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _FormDialog(
      title: widget.title,
      saveLabel: widget.saveLabel,
      saveKey: const Key('save-worker'),
      onSave: _save,
      error: _error,
      note: widget.note,
      children: [
        const Text('区分', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<WorkerKind>(
            key: const Key('worker-kind'),
            segments: [
              for (final kind in WorkerKind.values)
                ButtonSegment(
                  value: kind,
                  label: Text(kind.label, key: Key('kind-${kind.key}')),
                ),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('worker-name'),
          controller: _name,
          autofocus: widget.initialName.isEmpty,
          maxLength: 20,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: _contractor ? '会社名・屋号' : '名前',
            hintText: _contractor ? '例: 山田工業' : '例: 山田 太郎',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        const Text('給与の形', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PayType>(
            key: const Key('worker-pay-type'),
            segments: [
              for (final type in PayType.values)
                ButtonSegment(
                  value: type,
                  label: Text(type.label, key: Key('pay-${type.key}')),
                ),
            ],
            selected: {_payType},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _payType = value.first),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: Key('worker-rate-${_payType.key}'),
          controller: _rates[_payType],
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: _contractor && _payType == PayType.daily
                ? '単価（1人工あたり）'
                : _rateLabels[_payType],
            hintText: _rateHints[_payType],
            suffixText: '円',
            helperText: switch (_payType) {
              PayType.daily =>
                _contractor ? '金額 = 人工 × 単価（3人入れた日は3人工）' : '金額 = 人工 × 日当',
              PayType.hourly => '金額 = 勤務時間 × 時給（1人工 = 8時間）',
              PayType.monthly => '月給は出勤した月に1回だけ集計します',
            },
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('worker-overtime'),
          controller: _overtime,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: '残業単価（1時間あたり・任意）',
            hintText: '例: 2500',
            suffixText: '円',
          ),
        ),
      ],
    );
  }
}

class SiteDraft {
  const SiteDraft({
    required this.name,
    required this.note,
    this.address = '',
    this.isAreaSite = false,
    this.areaAmountMode = AreaAmountMode.areaTimesRate,
    this.areaSqm = 0,
    this.areaUnitPrice = 0,
    this.contractAmount = 0,
    this.settlementMonth = '',
  });

  final String name;
  final String note;
  final String address;
  final bool isAreaSite;
  final AreaAmountMode areaAmountMode;
  final double areaSqm;
  final int areaUnitPrice;
  final int contractAmount;
  final String settlementMonth;
}

Future<SiteDraft?> showSiteDialog(
  BuildContext context, {
  String title = '現場を追加',
  String saveLabel = '追加',
  String initialName = '',
  String initialNote = '',
  String initialAddress = '',
  bool initialIsAreaSite = false,
  AreaAmountMode initialAreaAmountMode = AreaAmountMode.areaTimesRate,
  double initialAreaSqm = 0,
  int initialAreaUnitPrice = 0,
  int initialContractAmount = 0,
  String initialSettlementMonth = '',
  DateTime? now,
}) {
  return showDialog<SiteDraft>(
    context: context,
    builder: (context) => _SiteDialog(
      title: title,
      saveLabel: saveLabel,
      initialName: initialName,
      initialNote: initialNote,
      initialAddress: initialAddress,
      initialIsAreaSite: initialIsAreaSite,
      initialAreaAmountMode: initialAreaAmountMode,
      initialAreaSqm: initialAreaSqm,
      initialAreaUnitPrice: initialAreaUnitPrice,
      initialContractAmount: initialContractAmount,
      initialSettlementMonth: initialSettlementMonth,
      now: now ?? DateTime.now(),
    ),
  );
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({
    required this.title,
    required this.saveLabel,
    required this.initialName,
    required this.initialNote,
    required this.initialAddress,
    required this.initialIsAreaSite,
    required this.initialAreaAmountMode,
    required this.initialAreaSqm,
    required this.initialAreaUnitPrice,
    required this.initialContractAmount,
    required this.initialSettlementMonth,
    required this.now,
  });

  final String title;
  final String saveLabel;
  final String initialName;
  final String initialNote;
  final String initialAddress;
  final bool initialIsAreaSite;
  final AreaAmountMode initialAreaAmountMode;
  final double initialAreaSqm;
  final int initialAreaUnitPrice;
  final int initialContractAmount;
  final String initialSettlementMonth;
  final DateTime now;

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _note = TextEditingController(text: widget.initialNote);
  late final _address = TextEditingController(text: widget.initialAddress);
  late final _sqm = TextEditingController(
    text: widget.initialAreaSqm > 0 ? formatUnits(widget.initialAreaSqm) : '',
  );
  late final _unitPrice = TextEditingController(
    text: widget.initialAreaUnitPrice > 0
        ? '${widget.initialAreaUnitPrice}'
        : '',
  );
  late final _contract = TextEditingController(
    text: widget.initialContractAmount > 0
        ? '${widget.initialContractAmount}'
        : '',
  );
  late bool _isArea = widget.initialIsAreaSite;
  late AreaAmountMode _mode = widget.initialAreaAmountMode;
  late String _settlement = widget.initialSettlementMonth.isEmpty
      ? monthKey(widget.now)
      : widget.initialSettlementMonth;
  String? _error;

  List<String> get _months {
    final first = DateTime(widget.now.year, widget.now.month - 24);
    return [
      for (var i = 0; i < 37; i++)
        monthKey(DateTime(first.year, first.month + i)),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _address.dispose();
    _sqm.dispose();
    _unitPrice.dispose();
    _contract.dispose();
    super.dispose();
  }

  int _parseYen(String raw, String label) {
    final text = raw.replaceAll(',', '').replaceAll('¥', '').trim();
    if (text.isEmpty) throw InvalidInput('$labelを入力してください。');
    final value = int.tryParse(text);
    if (value == null) throw InvalidInput('$labelは数字で入力してください。');
    return value;
  }

  double _parseSqm(String raw) {
    final text = raw.replaceAll(',', '').trim();
    if (text.isEmpty) throw const InvalidInput('平米数を入力してください。');
    final value = double.tryParse(text);
    if (value == null) throw const InvalidInput('平米数は数字で入力してください。');
    return value;
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '現場名を入力してください。');
      return;
    }
    var sqm = 0.0;
    var unit = 0;
    var contract = 0;
    if (_isArea) {
      try {
        if (_mode == AreaAmountMode.contract) {
          contract = _parseYen(_contract.text, '請負額');
        } else {
          sqm = _parseSqm(_sqm.text);
          unit = _parseYen(_unitPrice.text, '平米単価');
        }
      } on InvalidInput catch (e) {
        setState(() => _error = e.message);
        return;
      }
    } else {
      // Keep typed values so turning the switch back on is not a redo.
      sqm = double.tryParse(_sqm.text.replaceAll(',', '').trim()) ?? 0;
      unit =
          int.tryParse(_unitPrice.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      contract =
          int.tryParse(_contract.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    Navigator.pop(
      context,
      SiteDraft(
        name: _name.text,
        note: _note.text,
        address: _address.text,
        isAreaSite: _isArea,
        areaAmountMode: _mode,
        areaSqm: sqm,
        areaUnitPrice: unit,
        contractAmount: contract,
        settlementMonth: _settlement,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final months = _months;
    final settlement = months.contains(_settlement)
        ? _settlement
        : months.contains(monthKey(widget.now))
        ? monthKey(widget.now)
        : months.last;
    return _FormDialog(
      title: widget.title,
      saveLabel: widget.saveLabel,
      saveKey: const Key('save-site'),
      onSave: _save,
      error: _error,
      children: [
        TextField(
          key: const Key('site-name'),
          controller: _name,
          autofocus: widget.initialName.isEmpty,
          maxLength: 30,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '現場名',
            hintText: '例: 港北倉庫改修',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        TextField(
          key: const Key('site-address'),
          controller: _address,
          maxLength: maxSiteAddressLength,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '住所（任意）',
            hintText: '例: 横浜市港北区新横浜2-6-1',
            counterText: '',
            suffixIcon: _address.text.trim().isEmpty
                ? null
                : IconButton(
                    key: const Key('site-address-map'),
                    tooltip: '地図で開く',
                    icon: const Icon(Icons.map_outlined),
                    onPressed: () async {
                      final ok = await openAppleMaps(_address.text);
                      if (!ok && context.mounted) {
                        showSnack(context, '地図を開けませんでした。');
                      }
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('site-note'),
          controller: _note,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '元請・メモ（任意）',
            hintText: '例: 〇〇建設',
            counterText: '',
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          key: const Key('area-site-toggle'),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            '平米の現場',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('現場の金額を人工の割合で分ける。日当は付きません。'),
          value: _isArea,
          onChanged: (value) => setState(() => _isArea = value),
        ),
        if (_isArea) ...[
          const SizedBox(height: 4),
          SegmentedButton<AreaAmountMode>(
            key: const Key('area-amount-mode'),
            segments: const [
              ButtonSegment(
                value: AreaAmountMode.areaTimesRate,
                label: Text('平米数×単価'),
              ),
              ButtonSegment(value: AreaAmountMode.contract, label: Text('請負額')),
            ],
            selected: {_mode},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _mode = value.first),
          ),
          const SizedBox(height: 12),
          if (_mode == AreaAmountMode.areaTimesRate) ...[
            TextField(
              key: const Key('area-sqm'),
              controller: _sqm,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '平米数',
                hintText: '例: 120',
                suffixText: '㎡',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('area-unit-price'),
              controller: _unitPrice,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '平米単価',
                hintText: '例: 3000',
                suffixText: '円',
              ),
            ),
          ] else
            TextField(
              key: const Key('area-contract'),
              controller: _contract,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '請負額',
                hintText: '例: 360000',
                suffixText: '円',
              ),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('area-settlement-month'),
            // ignore: deprecated_member_use
            value: settlement,
            decoration: const InputDecoration(
              labelText: '集計月',
              helperText: '月をまたぐ現場は、この月にまとめて分けます。仕事が終わった月にしてください。',
              helperMaxLines: 3,
            ),
            items: [
              for (final key in months)
                DropdownMenuItem(value: key, child: Text(_labelMonth(key))),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _settlement = value);
            },
          ),
        ],
      ],
    );
  }

  String _labelMonth(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null) return key;
    return formatMonth(DateTime(year, month));
  }
}

class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.title,
    required this.saveLabel,
    required this.saveKey,
    required this.onSave,
    required this.error,
    required this.children,
    this.note,
  });

  final String title;
  final String saveLabel;
  final Key saveKey;
  final VoidCallback onSave;
  final String? error;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            ...children,
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note!,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: saveKey,
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 46),
                  ),
                  child: Text(saveLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded panel used across screens.
class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = AppColors.card,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Material (not a decorated box) so ListTile ink shows inside.
    return Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// `‹ 2026年10月 ›` header shared by the calendar and the summary.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    this.locked = false,
    super.key,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          key: const Key('month-prev'),
          tooltip: '前の月',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left, size: 30),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                formatMonth(month),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (locked) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.lock_outline,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ],
          ),
        ),
        IconButton(
          key: const Key('month-next'),
          tooltip: '次の月',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, size: 30),
        ),
      ],
    );
  }
}
