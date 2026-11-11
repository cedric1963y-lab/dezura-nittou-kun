import 'package:flutter/material.dart';

import '../errors.dart';
import '../format.dart';
import '../models/records.dart';
import '../screens/premium_screen.dart';
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
  });

  final String name;
  final PayType payType;
  final int dayRate;
  final int hourlyRate;
  final int monthlySalary;
  final int overtimeRate;
}

Future<WorkerDraft?> showWorkerDialog(
  BuildContext context, {
  String title = '職人を追加',
  String saveLabel = '追加',
  String initialName = '',
  int? initialDayRate,
  int initialOvertimeRate = 0,
  PayType initialPayType = PayType.daily,
  int initialHourlyRate = 0,
  int initialMonthlySalary = 0,
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
        PayType.monthly: initialMonthlySalary == 0 ? null : initialMonthlySalary,
      },
      initialPayType: initialPayType,
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
    required this.initialOvertimeRate,
    required this.note,
  });

  final String title;
  final String saveLabel;
  final String initialName;
  final Map<PayType, int?> initialRates;
  final PayType initialPayType;
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
  String? _error;

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
      setState(() => _error = '名前を入力してください。');
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
        TextField(
          key: const Key('worker-name'),
          controller: _name,
          autofocus: widget.initialName.isEmpty,
          maxLength: 20,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '名前',
            hintText: '例: 山田 太郎',
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
            labelText: _rateLabels[_payType],
            hintText: _rateHints[_payType],
            suffixText: '円',
            helperText: switch (_payType) {
              PayType.daily => '金額 = 人工 × 日当',
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
  const SiteDraft({required this.name, required this.note});

  final String name;
  final String note;
}

Future<SiteDraft?> showSiteDialog(
  BuildContext context, {
  String title = '現場を追加',
  String saveLabel = '追加',
  String initialName = '',
  String initialNote = '',
}) {
  return showDialog<SiteDraft>(
    context: context,
    builder: (context) => _SiteDialog(
      title: title,
      saveLabel: saveLabel,
      initialName: initialName,
      initialNote: initialNote,
    ),
  );
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({
    required this.title,
    required this.saveLabel,
    required this.initialName,
    required this.initialNote,
  });

  final String title;
  final String saveLabel;
  final String initialName;
  final String initialNote;

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _note = TextEditingController(text: widget.initialNote);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '現場名を入力してください。');
      return;
    }
    Navigator.pop(context, SiteDraft(name: _name.text, note: _note.text));
  }

  @override
  Widget build(BuildContext context) {
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
        TextField(
          key: const Key('site-note'),
          controller: _note,
          maxLength: 40,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            labelText: '元請・メモ（任意）',
            hintText: '例: 〇〇建設',
            counterText: '',
          ),
        ),
      ],
    );
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
                  style: FilledButton.styleFrom(minimumSize: const Size(96, 46)),
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
                const Icon(Icons.lock_outline, size: 18, color: AppColors.muted),
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
