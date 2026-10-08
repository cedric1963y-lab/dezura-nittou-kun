import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../errors.dart';
import '../format.dart';
import '../logic/summary.dart';
import '../services/share_service.dart';
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
        const _SectionTitle('職人別'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < summary.workers.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _Row(
                  title: summary.workers[i].worker.name,
                  detail: [
                    '${formatUnits(summary.workers[i].units)}人工',
                    '${summary.workers[i].days}日',
                    if (summary.workers[i].overtimeHours > 0)
                      '残業${formatHours(summary.workers[i].overtimeHours)}',
                  ].join('・'),
                  amount: summary.workers[i].amount,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('現場別'),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < summary.sites.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _Row(
                  title: summary.sites[i].site.name,
                  detail:
                      '${formatUnits(summary.sites[i].units)}人工・${summary.sites[i].workerCount}人',
                  amount: summary.sites[i].amount,
                ),
              ],
            ],
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
    ];
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
            '${summary.month.month}月の日当合計',
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
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
  const _Row({required this.title, required this.detail, required this.amount});

  final String title;
  final String detail;
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
