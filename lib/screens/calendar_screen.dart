import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../errors.dart';
import '../format.dart';
import '../models/records.dart';
import '../plan/limits.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import 'record_sheet.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime? _month;
  DateTime? _day;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_month == null) {
      final now = AppScope.of(context).now;
      _month = DateTime(now.year, now.month);
      _day = DateTime(now.year, now.month, now.day);
    }
  }

  void _changeMonth(AppController controller, int delta) {
    final next = addMonths(_month!, delta);
    final now = controller.now;
    if (next.isAfter(DateTime(now.year, now.month))) return;
    if (!controller.canOpenMonth(next)) {
      openPremium(context, reason: LimitKind.history);
      return;
    }
    setState(() {
      _month = next;
      _day = isSameMonth(next, now)
          ? DateTime(now.year, now.month, now.day)
          : DateTime(next.year, next.month, 1);
    });
  }

  void _goToday(AppController controller) {
    final now = controller.now;
    setState(() {
      _month = DateTime(now.year, now.month);
      _day = DateTime(now.year, now.month, now.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final month = _month!;
    final day = _day!;
    final now = controller.now;
    final atCurrentMonth = isSameMonth(month, now);
    final dayRecords = controller.recordsOn(day);
    final dayUnits = dayRecords.fold<double>(0, (sum, r) => sum + r.units);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppInfo.name),
        actions: [
          TextButton(
            onPressed: () => _goToday(controller),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('今日'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          MonthSwitcher(
            month: month,
            onPrevious: () => _changeMonth(controller, -1),
            onNext: atCurrentMonth ? null : () => _changeMonth(controller, 1),
          ),
          _MonthGrid(
            month: month,
            selected: day,
            today: now,
            unitsByDay: controller.unitsByDay(month),
            onSelect: (value) => setState(() => _day = value),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatDayHeading(day)}の出面',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${formatUnits(dayUnits)}人工',
                key: const Key('day-units'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.sites.isEmpty || controller.workers.isEmpty)
            _SetupCard(controller: controller)
          else ...[
            _SitePicker(controller: controller),
            const SizedBox(height: 8),
            for (final worker in controller.workers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WorkerTile(
                  worker: worker,
                  record: controller.recordFor(worker.id, day),
                  siteName: (record) =>
                      controller.siteById(record.siteId)?.name ?? '',
                  showSite: (record) =>
                      record.siteId != controller.selectedSite?.id,
                  onTap: () =>
                      guard(context, () => controller.tapWorker(worker.id, day)),
                  onEdit: () => showRecordSheet(
                    context,
                    worker: worker,
                    day: day,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('mark-all'),
                    onPressed: () => guard(context, () async {
                      final added = await controller.markAll(day);
                      if (!context.mounted) return;
                      showSnack(
                        context,
                        added == 0
                            ? '全員すでに付いています。'
                            : '$added人を1人工で付けました。',
                      );
                    }),
                    icon: const Icon(Icons.done_all),
                    label: const Text('全員 1人工'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'タップで「1人工 → 半日 → 取消」。現場の変更や残業は右の「…」から。',
              style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.unitsByDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final Map<int, double> unitsByDay;
  final ValueChanged<DateTime> onSelect;

  static const _labels = ['日', '月', '火', '水', '木', '金', '土'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday % 7; // Sunday first
    final days = daysInMonth(month);
    final cells = leading + days;
    final rows = (cells / 7).ceil();

    Color labelColor(int column) {
      if (column == 0) return AppColors.sunday;
      if (column == 6) return AppColors.saturday;
      return AppColors.muted;
    }

    return Panel(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      child: Column(
        children: [
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Center(
                    child: Text(
                      _labels[c],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: labelColor(c),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(child: _cell(r * 7 + c - leading + 1, c, days)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(int dayNumber, int column, int days) {
    if (dayNumber < 1 || dayNumber > days) return const SizedBox(height: 48);
    final date = DateTime(month.year, month.month, dayNumber);
    final isSelected = isSameDay(date, selected);
    final isToday = isSameDay(date, today);
    final isFuture = date.isAfter(today);
    final units = unitsByDay[dayNumber] ?? 0;
    var color = AppColors.ink;
    if (column == 0) color = AppColors.sunday;
    if (column == 6) color = AppColors.saturday;
    if (isSelected) color = Colors.white;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? AppColors.navy : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('day-$dayNumber'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(date),
          child: Container(
            height: 44,
            decoration: isToday && !isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.amber, width: 2),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isFuture && !isSelected
                        ? color.withValues(alpha: 0.45)
                        : color,
                  ),
                ),
                const SizedBox(height: 1),
                if (units > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.amber : AppColors.amberSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      formatUnits(units),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SitePicker extends StatelessWidget {
  const _SitePicker({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final site = controller.selectedSite;
    return Panel(
      padding: EdgeInsets.zero,
      child: ListTile(
        key: const Key('site-picker'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: const Icon(Icons.apartment, color: AppColors.navy),
        title: Text(
          site?.name ?? '現場を選ぶ',
          style: const TextStyle(fontWeight: FontWeight.w800),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          site == null || site.note.isEmpty ? 'タップで付ける現場' : site.note,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.unfold_more),
        onTap: () => _pick(context),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final c = AppScope.of(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'タップで付ける現場',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              for (final s in c.sites)
                ListTile(
                  leading: Icon(
                    s.id == c.selectedSite?.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: AppColors.navy,
                  ),
                  title: Text(s.name),
                  subtitle: s.note.isEmpty ? null : Text(s.note),
                  onTap: () async {
                    await c.selectSite(s.id);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add, color: AppColors.navy),
                title: const Text('現場を追加'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (!c.canAddSite) {
                    await openPremium(context, reason: LimitKind.sites);
                    return;
                  }
                  final draft = await showSiteDialog(context);
                  if (draft == null || !context.mounted) return;
                  await guard(
                    context,
                    () => c.addSite(name: draft.name, note: draft.note),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({
    required this.worker,
    required this.record,
    required this.siteName,
    required this.showSite,
    required this.onTap,
    required this.onEdit,
  });

  final Worker worker;
  final DayRecord? record;
  final String Function(DayRecord record) siteName;
  final bool Function(DayRecord record) showSite;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final details = <String>[
      '日当 ${formatYen(worker.dayRate)}',
      if (r != null && r.overtimeHours > 0) '残業${formatHours(r.overtimeHours)}',
      if (r != null && showSite(r)) siteName(r),
    ];
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('worker-${worker.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: r == null ? AppColors.line : AppColors.navy,
              width: r == null ? 1 : 1.4,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: r == null ? AppColors.paper : AppColors.amberSoft,
                foregroundColor: AppColors.navy,
                child: Text(
                  worker.name.characters.first,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details.join('・'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(units: r?.units),
              IconButton(
                key: Key('edit-${worker.id}'),
                tooltip: '現場・残業',
                onPressed: onEdit,
                icon: const Icon(Icons.more_horiz, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.units});

  final double? units;

  @override
  Widget build(BuildContext context) {
    final u = units;
    final Color background;
    final Color foreground;
    final String label;
    if (u == null) {
      background = AppColors.paper;
      foreground = AppColors.muted;
      label = '未';
    } else if (u >= 1) {
      background = AppColors.navy;
      foreground = Colors.white;
      label = '1人工';
    } else {
      background = AppColors.amber;
      foreground = AppColors.ink;
      label = '半日';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 72,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final needsSite = controller.sites.isEmpty;
    final needsWorker = controller.workers.isEmpty;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'はじめに',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '現場と職人（自分も含めて）を登録すると、ここで毎日の出面をタップで付けられます。',
            style: TextStyle(height: 1.45),
          ),
          const SizedBox(height: 12),
          if (needsSite)
            FilledButton.icon(
              key: const Key('setup-site'),
              onPressed: () async {
                final draft = await showSiteDialog(context);
                if (draft == null || !context.mounted) return;
                await guard(
                  context,
                  () => controller.addSite(name: draft.name, note: draft.note),
                );
              },
              icon: const Icon(Icons.apartment),
              label: const Text('現場を登録'),
            ),
          if (needsSite && needsWorker) const SizedBox(height: 8),
          if (needsWorker)
            FilledButton.icon(
              key: const Key('setup-worker'),
              onPressed: () async {
                final draft = await showWorkerDialog(context);
                if (draft == null || !context.mounted) return;
                await guard(
                  context,
                  () => controller.addWorker(
                    name: draft.name,
                    dayRate: draft.dayRate,
                    overtimeRate: draft.overtimeRate,
                  ),
                );
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('職人を登録'),
            ),
          const SizedBox(height: 10),
          Text(
            '無料プランは職人${PlanLimits.freeWorkerLimit}人・現場${PlanLimits.freeSiteLimit}か所までです。',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
