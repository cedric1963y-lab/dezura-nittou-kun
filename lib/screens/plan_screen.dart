import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../format.dart';
import '../models/plans.dart';
import '../models/records.dart';
import '../services/share_service.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

/// Make tomorrow's (or any day's) work plan and share it as an image.
/// Free for every user; 出面 records are not touched until the optional
/// 「この予定で出面をつける」 button is used.
class PlanScreen extends StatefulWidget {
  const PlanScreen({this.initialDay, this.openImage = false, super.key});

  /// Defaults to tomorrow.
  final DateTime? initialDay;

  /// Debug screenshot hook: open the generated image immediately.
  final bool openImage;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  DateTime? _day;
  var _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_day == null) {
      final now = AppScope.of(context).now;
      _day = widget.initialDay ?? tomorrowOf(now);
    }
    if (widget.openImage && !_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openImage();
      });
    }
  }

  DateTime _today() {
    final now = AppScope.of(context).now;
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _minDay() =>
      _today().subtract(const Duration(days: planRetentionDays));

  DateTime _maxDay() {
    final today = _today();
    return DateTime(today.year, today.month, today.day + planRetentionDays);
  }

  void _shiftDay(int delta) {
    final current = _day!;
    final next = DateTime(current.year, current.month, current.day + delta);
    if (next.isBefore(_minDay()) || next.isAfter(_maxDay())) return;
    setState(() => _day = next);
  }

  Future<void> _share(AppController controller) async {
    final day = _day!;
    final origin = shareOriginOf(context);
    final ok = await guard(context, () async {
      final path = await controller.exportPlanImage(day);
      if (!mounted) return;
      await shareFile(
        path: path,
        fileName: planFileName(day),
        mimeType: 'image/png',
        subject: formatPlanTitle(day),
        origin: origin,
      );
    });
    if (ok && mounted) {
      showSnack(context, '共有シートを開きました。');
    }
  }

  Future<void> _apply(AppController controller) async {
    final day = _day!;
    if (controller.planFor(day).isEmpty) {
      showSnack(context, '予定がまだありません。');
      return;
    }
    if (!controller.canOpenMonth(day)) {
      await openPremium(context, reason: null);
      if (mounted) {
        showSnack(context, '出面を付けられるのは、無料プランでは今月だけです。');
      }
      return;
    }
    final ok = await confirmAction(
      context,
      title: '${formatDayHeading(day)}の出面を付けますか？',
      body: 'この予定の職人を1人工で付けます。すでに出面がある人はそのままです。予定そのものは変わりません。',
      confirmLabel: '出面をつける',
    );
    if (!ok || !mounted) return;
    await guard(context, () async {
      final added = await controller.applyPlanAsAttendance(day);
      if (!mounted) return;
      showSnack(
        context,
        added == 0 ? 'すでに出面が付いているか、対象がいません。' : '$added人を1人工で付けました。',
      );
    });
  }

  Future<void> _clear(AppController controller) async {
    final ok = await confirmAction(
      context,
      title: '${formatDayHeading(_day!)}の予定を消しますか？',
      body: '出面の記録は消えません。',
      confirmLabel: '予定を消す',
    );
    if (!ok || !mounted) return;
    await guard(context, () => controller.clearPlan(_day!));
  }

  Future<void> _openImage() async {
    final day = _day!;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlanImagePreviewScreen(day: day)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final day = _day!;
    final plan = controller.planFor(day);
    final now = controller.now;
    final today = DateTime(now.year, now.month, now.day);
    final isTomorrow = isSameDay(day, tomorrowOf(now));
    final isToday = isSameDay(day, today);

    return Scaffold(
      appBar: AppBar(title: Text(isTomorrow ? '明日の予定' : '予定')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('plan-day-prev'),
                tooltip: '前の日',
                onPressed: _day!.isAfter(_minDay())
                    ? () => _shiftDay(-1)
                    : null,
                icon: const Icon(Icons.chevron_left, size: 30),
              ),
              Expanded(
                child: Text(
                  formatPlanTitle(day),
                  key: const Key('plan-day'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: const Key('plan-day-next'),
                tooltip: '次の日',
                onPressed: _day!.isBefore(_maxDay())
                    ? () => _shiftDay(1)
                    : null,
                icon: const Icon(Icons.chevron_right, size: 30),
              ),
            ],
          ),
          if (isToday || isTomorrow)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isTomorrow ? '明日' : '今日',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const Text(
            '職人を現場にタップして割り当てます。画像には現場・住所・メモと名前だけが出ます。日当や金額は入りません。',
            style: TextStyle(color: AppColors.muted, height: 1.45),
          ),
          const SizedBox(height: 12),
          if (controller.sites.isEmpty || controller.workers.isEmpty)
            const Panel(
              child: Text(
                '先に「名簿」で現場と職人を登録してください。',
                style: TextStyle(height: 1.45),
              ),
            )
          else
            for (final site in controller.sites) ...[
              _SitePlanCard(
                site: site,
                workers: controller.workers,
                assigned: plan.site(site.id).workerIds,
                note: plan.site(site.id).note,
                onToggle: (workerId) => guard(
                  context,
                  () => controller.togglePlanWorker(
                    day: day,
                    siteId: site.id,
                    workerId: workerId,
                  ),
                ),
                onNote: (note) => guard(
                  context,
                  () => controller.setPlanNote(
                    day: day,
                    siteId: site.id,
                    note: note,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 6),
          FilledButton.icon(
            key: const Key('plan-share-image'),
            onPressed: plan.isEmpty ? null : () => _share(controller),
            icon: const Icon(Icons.ios_share),
            label: const Text('画像でLINEに送る'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('plan-apply'),
            onPressed: plan.isEmpty ? null : () => _apply(controller),
            icon: const Icon(Icons.how_to_reg_outlined),
            label: const Text('この予定で出面をつける'),
          ),
          if (!plan.isEmpty) ...[
            const SizedBox(height: 4),
            TextButton(
              key: const Key('plan-clear'),
              onPressed: () => _clear(controller),
              child: const Text('この日の予定を消す'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SitePlanCard extends StatefulWidget {
  const _SitePlanCard({
    required this.site,
    required this.workers,
    required this.assigned,
    required this.note,
    required this.onToggle,
    required this.onNote,
  });

  final Site site;
  final List<Worker> workers;
  final List<String> assigned;
  final String note;
  final Future<bool> Function(String workerId) onToggle;
  final Future<bool> Function(String note) onNote;

  @override
  State<_SitePlanCard> createState() => _SitePlanCardState();
}

class _SitePlanCardState extends State<_SitePlanCard> {
  late final _note = TextEditingController(text: widget.note);

  @override
  void didUpdateWidget(covariant _SitePlanCard old) {
    super.didUpdateWidget(old);
    if (old.note != widget.note && _note.text != widget.note) {
      _note.text = widget.note;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            site.name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (site.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              site.address,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in widget.workers)
                FilterChip(
                  key: Key('plan-worker-${site.id}-${w.id}'),
                  label: Text(
                    w.kind == WorkerKind.contractor ? '${w.name}（外注）' : w.name,
                  ),
                  selected: widget.assigned.contains(w.id),
                  onSelected: (_) => widget.onToggle(w.id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: Key('plan-note-${site.id}'),
            controller: _note,
            maxLength: maxPlanNoteLength,
            decoration: const InputDecoration(
              labelText: 'メモ（任意）',
              hintText: '例: 集合8時',
              counterText: '',
            ),
            onChanged: (value) => widget.onNote(value),
          ),
        ],
      ),
    );
  }
}

/// Full-screen preview of the generated 予定 image (also used for screenshots).
class PlanImagePreviewScreen extends StatefulWidget {
  const PlanImagePreviewScreen({required this.day, super.key});

  final DateTime day;

  @override
  State<PlanImagePreviewScreen> createState() => _PlanImagePreviewScreenState();
}

class _PlanImagePreviewScreenState extends State<PlanImagePreviewScreen> {
  Future<Uint8List>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= AppScope.of(context).planImageBytes(widget.day);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text(formatPlanTitle(widget.day))),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('画像を作れませんでした。'));
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            child: Center(
              child: Image.memory(
                bytes,
                key: const Key('plan-image'),
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
