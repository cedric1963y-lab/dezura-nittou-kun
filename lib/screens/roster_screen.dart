import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../errors.dart';
import '../format.dart';
import '../plan/limits.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

enum _RosterTab { workers, sites }

/// 名簿: workers with their day rates, and sites.
class RosterScreen extends StatefulWidget {
  const RosterScreen({super.key});

  @override
  State<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends State<RosterScreen> {
  var _tab = _RosterTab.workers;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final workersTab = _tab == _RosterTab.workers;
    return Scaffold(
      appBar: AppBar(title: const Text('名簿')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('roster-add'),
        onPressed: () =>
            workersTab ? _addWorker(controller) : _addSite(controller),
        icon: const Icon(Icons.add),
        label: Text(workersTab ? '職人を追加' : '現場を追加'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
        children: [
          SegmentedButton<_RosterTab>(
            segments: const [
              ButtonSegment(
                value: _RosterTab.workers,
                icon: Icon(Icons.engineering_outlined),
                label: Text('職人'),
              ),
              ButtonSegment(
                value: _RosterTab.sites,
                icon: Icon(Icons.apartment),
                label: Text('現場'),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
          const SizedBox(height: 10),
          if (!controller.premium)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '無料プラン：職人 ${controller.workers.length}/${PlanLimits.freeWorkerLimit}人・現場 ${controller.sites.length}/${PlanLimits.freeSiteLimit}か所',
                key: const Key('roster-usage'),
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
          if (workersTab) ..._workers(controller) else ..._sites(controller),
        ],
      ),
    );
  }

  List<Widget> _workers(AppController controller) {
    if (controller.workers.isEmpty) {
      return const [
        Panel(child: Text('職人がまだいません。自分も1人として登録してください。')),
      ];
    }
    return [
      for (final w in controller.workers)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              leading: CircleAvatar(
                backgroundColor: AppColors.amberSoft,
                foregroundColor: AppColors.navy,
                child: Text(w.name.characters.first),
              ),
              title: Text(
                w.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  '日当 ${formatYen(w.dayRate)}',
                  if (w.overtimeRate > 0) '残業 ${formatYen(w.overtimeRate)}/h',
                ].join('・'),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => value == 'edit'
                    ? _editWorker(controller, w.id)
                    : _deleteWorker(controller, w.id),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('編集')),
                  PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
              onTap: () => _editWorker(controller, w.id),
            ),
          ),
        ),
    ];
  }

  List<Widget> _sites(AppController controller) {
    if (controller.sites.isEmpty) {
      return const [Panel(child: Text('現場がまだありません。'))];
    }
    return [
      for (final s in controller.sites)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              leading: const Icon(Icons.apartment, color: AppColors.navy),
              title: Text(
                s.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                [
                  if (s.note.isNotEmpty) s.note,
                  '出面 ${controller.recordCountForSite(s.id)}件',
                ].join('・'),
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => value == 'edit'
                    ? _editSite(controller, s.id)
                    : _deleteSite(controller, s.id),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('編集')),
                  PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
              onTap: () => _editSite(controller, s.id),
            ),
          ),
        ),
    ];
  }

  Future<void> _addWorker(AppController controller) async {
    if (!controller.canAddWorker) {
      await openPremium(context, reason: LimitKind.workers);
      return;
    }
    final draft = await showWorkerDialog(context);
    if (draft == null || !mounted) return;
    await guard(
      context,
      () => controller.addWorker(
        name: draft.name,
        dayRate: draft.dayRate,
        overtimeRate: draft.overtimeRate,
      ),
    );
  }

  Future<void> _editWorker(AppController controller, String id) async {
    final w = controller.workerById(id);
    if (w == null) return;
    final draft = await showWorkerDialog(
      context,
      title: '職人を編集',
      saveLabel: '保存',
      initialName: w.name,
      initialDayRate: w.dayRate,
      initialOvertimeRate: w.overtimeRate,
      note: '日当・残業単価の変更は、今月1日以降の出面に反映されます。先月までの金額は変わりません。',
    );
    if (draft == null || !mounted) return;
    await guard(
      context,
      () => controller.updateWorker(
        id: id,
        name: draft.name,
        dayRate: draft.dayRate,
        overtimeRate: draft.overtimeRate,
      ),
    );
  }

  Future<void> _deleteWorker(AppController controller, String id) async {
    final w = controller.workerById(id);
    if (w == null) return;
    final count = controller.recordCountForWorker(id);
    final ok = await confirmAction(
      context,
      title: '${w.name}を削除しますか？',
      body: count == 0
          ? '名簿から外します。'
          : 'この人の出面$count件も一緒に消えます。元に戻せません。',
      confirmLabel: '削除',
    );
    if (!ok || !mounted) return;
    await guard(context, () => controller.deleteWorker(id));
  }

  Future<void> _addSite(AppController controller) async {
    if (!controller.canAddSite) {
      await openPremium(context, reason: LimitKind.sites);
      return;
    }
    final draft = await showSiteDialog(context);
    if (draft == null || !mounted) return;
    await guard(
      context,
      () => controller.addSite(name: draft.name, note: draft.note),
    );
  }

  Future<void> _editSite(AppController controller, String id) async {
    final s = controller.siteById(id);
    if (s == null) return;
    final draft = await showSiteDialog(
      context,
      title: '現場を編集',
      saveLabel: '保存',
      initialName: s.name,
      initialNote: s.note,
    );
    if (draft == null || !mounted) return;
    await guard(
      context,
      () => controller.updateSite(id: id, name: draft.name, note: draft.note),
    );
  }

  Future<void> _deleteSite(AppController controller, String id) async {
    final s = controller.siteById(id);
    if (s == null) return;
    final count = controller.recordCountForSite(id);
    final ok = await confirmAction(
      context,
      title: '${s.name}を削除しますか？',
      body: count == 0 ? '現場の一覧から外します。' : 'この現場の出面$count件も一緒に消えます。元に戻せません。',
      confirmLabel: '削除',
    );
    if (!ok || !mounted) return;
    await guard(context, () => controller.deleteSite(id));
  }
}
