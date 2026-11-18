import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../errors.dart';
import '../format.dart';
import '../models/records.dart';
import '../logic/summary.dart';
import '../services/links.dart';
import '../services/share_service.dart';
import '../services/toolbox.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import 'export_screen.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  DateTime? _month;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_month == null) {
      final now = AppScope.of(context).now;
      _month = DateTime(now.year, now.month);
    }
  }

  void _changeMonth(AppController controller, int delta) {
    final next = addMonths(_month!, delta);
    final now = controller.now;
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final month = _month!;
    final open = controller.canOpenMonth(month);
    final atCurrentMonth = isSameMonth(month, controller.now);

    return Scaffold(
      appBar: AppBar(title: const Text('集計')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          MonthSwitcher(
            month: month,
            locked: !open,
            onPrevious: () => _changeMonth(controller, -1),
            onNext: atCurrentMonth ? null : () => _changeMonth(controller, 1),
          ),
          if (!open)
            const _LockedMonth()
          else
            ..._summary(context, controller, controller.summaryFor(month)),
        ],
      ),
    );
  }

  List<Widget> _summary(
    BuildContext context,
    AppController controller,
    MonthSummary summary,
  ) {
    return [
      _TotalCard(summary: summary),
      const SizedBox(height: 16),
      if (summary.isEmpty)
        const Panel(
          child: Text(
            'この月の出面はまだありません。「出面」タブで職人をタップすると、ここに集計されます。',
            style: TextStyle(height: 1.45),
          ),
        )
      else ...[
        if (summary.hasContractor) ...[
          for (final kind in WorkerKind.values)
            if (summary.workersOf(kind).isNotEmpty) ...[
              _SectionTitle(kind.label),
              _WorkerList(
                workers: summary.workersOf(kind),
                subtotalLabel: '${kind.label} 小計',
                subtotalUnits: summary.unitsOf(kind),
                subtotalAmount: summary.amountOf(kind),
                subtotalKey: Key('subtotal-${kind.key}'),
              ),
              const SizedBox(height: 12),
            ],
          Panel(
            color: AppColors.paper,
            child: Row(
              key: const Key('grand-total'),
              children: [
                const Text(
                  '合計（従業員＋外注）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '${formatUnits(summary.units)}人工　${formatYen(summary.amount)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          const _SectionTitle('職人別'),
          _WorkerList(workers: summary.workers),
        ],
        const SizedBox(height: 16),
        const _SectionTitle('現場別'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < summary.sites.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _Row(
                  title: summary.sites[i].site.isAreaSite
                      ? '${summary.sites[i].site.name}（平米）'
                      : summary.sites[i].site.name,
                  detail:
                      '${formatUnits(summary.sites[i].units)}人工・${summary.sites[i].workerCount}人${summary.sites[i].nightUnits > 0 ? '\n昼${formatUnits(summary.sites[i].dayUnits)}人工・夜勤${formatUnits(summary.sites[i].nightUnits)}人工' : ''}',
                  extraLines: [
                    if (summary.sites[i].allowance > 0 ||
                        summary.sites[i].areaAmount > 0) ...[
                      if (summary.sites[i].wageAmount > 0)
                        '日当　${formatYen(summary.sites[i].wageAmount)}',
                      if (summary.sites[i].allowance > 0)
                        '色付け　${formatYen(summary.sites[i].allowance)}',
                      if (summary.sites[i].areaAmount > 0)
                        '平米割り　${formatYen(summary.sites[i].areaAmount)}',
                    ],
                  ],
                  amount: summary.sites[i].amount,
                ),
              ],
            ],
          ),
        ),
        if (summary.hasMonthly)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              monthlySiteNote,
              key: Key('monthly-site-note'),
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        if (summary.hasArea)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              areaSiteNote,
              key: Key('area-site-note'),
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
      ],
      const SizedBox(height: 18),
      Builder(
        builder: (buttonContext) => FilledButton.icon(
          key: const Key('share-text'),
          onPressed: () => guard(context, () async {
            final text = controller.textFor(summary.month);
            await shareText(
              text,
              subject: '出面・日当 ${formatMonth(summary.month)}',
              origin: shareOriginOf(buttonContext),
            );
          }),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('LINEなどにテキストで送る'),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('open-export'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExportScreen(month: summary.month),
          ),
        ),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('出面表PDF・CSV'),
      ),
      if (!summary.isEmpty) ...[
        const SizedBox(height: 16),
        const _MitsumoriPrompt(),
      ],
    ];
  }
}

class _WorkerList extends StatelessWidget {
  const _WorkerList({
    required this.workers,
    this.subtotalLabel,
    this.subtotalUnits = 0,
    this.subtotalAmount = 0,
    this.subtotalKey,
  });

  final List<WorkerTotal> workers;
  final String? subtotalLabel;
  final double subtotalUnits;
  final int subtotalAmount;
  final Key? subtotalKey;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < workers.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _Row(
              title: workers[i].worker.name,
              detail: [
                workers[i].payName,
                workerDetail(workers[i]),
                if (workers[i].overtimeHours > 0)
                  '残業${formatHours(workers[i].overtimeHours)}',
              ].join('・'),
              extraLines: [
                if (workers[i].breakdown.length > 1)
                  for (final row in workers[i].breakdown)
                    '${breakdownLabel(row)}　${formatUnits(row.units)}人工',
                if (workers[i].allowance > 0 || workers[i].areaAmount > 0) ...[
                  if (workers[i].wageAmount > 0 || workers[i].salary > 0)
                    '日当　${formatYen(workers[i].wageAmount + workers[i].salary)}',
                  if (workers[i].allowance > 0)
                    '色付け　${formatYen(workers[i].allowance)}',
                  if (workers[i].areaAmount > 0)
                    '平米割り　${formatYen(workers[i].areaAmount)}',
                ],
              ],
              amount: workers[i].amount,
            ),
          ],
          if (subtotalLabel != null) ...[
            const Divider(height: 1),
            Container(
              color: AppColors.paper,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                key: subtotalKey,
                children: [
                  Text(
                    subtotalLabel!,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    '${formatUnits(subtotalUnits)}人工　${formatYen(subtotalAmount)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.workers.every((w) => w.payType == PayType.daily)
                ? '${summary.month.month}月の日当合計'
                : '${summary.month.month}月の支払合計',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            formatYen(summary.amount),
            key: const Key('total-amount'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: '人工', value: formatUnits(summary.units)),
              _Stat(label: '稼働日', value: '${summary.workingDays}日'),
              _Stat(label: '残業', value: formatHours(summary.overtimeHours)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.amber,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.detail,
    required this.amount,
    this.extraLines = const [],
  });

  final String title;
  final String detail;
  final List<String> extraLines;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                for (final line in extraLines)
                  Text(
                    '└ $line',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatYen(amount),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _MitsumoriPrompt extends StatelessWidget {
  const _MitsumoriPrompt();

  @override
  Widget build(BuildContext context) {
    final app = ConstructionApps.mitsumori;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '月末の集計を、見積に使う',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            '${app.name}で、この月の人工費を見積の一行にできます。',
            style: const TextStyle(height: 1.45, color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const Key('mitsumori-prompt'),
            onPressed: () async {
              final ok = await openExternal(app.storeUrl);
              if (!ok && context.mounted) {
                showSnack(context, 'ページを開けませんでした。');
              }
            },
            child: const Text('見積・請求くんを見る'),
          ),
        ],
      ),
    );
  }
}

class _LockedMonth extends StatelessWidget {
  const _LockedMonth();

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_outline, size: 36, color: AppColors.navy),
          const SizedBox(height: 8),
          const Text(
            '過去の月はプレミアムで見られます',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            '無料プランでは今月の集計を見られます。付けた出面は消えずにこのiPhoneに残っています。',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.45, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('unlock-history'),
            onPressed: () => openPremium(context, reason: LimitKind.history),
            child: const Text('プレミアムを見る'),
          ),
        ],
      ),
    );
  }
}
