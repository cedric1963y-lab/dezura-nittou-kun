import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/review_prompt.dart';
import '../format.dart';
import '../models/records.dart';
import 'calendar_screen.dart';
import 'record_sheet.dart';
import 'export_screen.dart';
import 'premium_screen.dart';
import 'roster_screen.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';
import 'plan_screen.dart';
import 'worker_pdf_screen.dart';

/// Bottom tabs: 出面 / 集計 / 名簿 / 設定.
class HomeShell extends StatefulWidget {
  const HomeShell({this.startTab = 0, super.key});

  /// 0-3 picks a tab. Debug screenshot runs also use 10 (集計 then 出力),
  /// 11 (プレミアム), 12 (平米の現場の編集), 13 (職人の道具箱), 14 (色付け),
  /// 15 (交通費・駐車場代), 16 (個人明細PDF), 17 (現場の住所編集),
  /// 18 (人工のチップ), 19 (住所つき集計), 20 (住所つき個人明細PDF),
  /// 21 (明日の予定), 22 (予定の画像).
  final int startTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = switch (widget.startTab) {
    10 => 1,
    12 => 2,
    13 => 3,
    16 => 1,
    17 => 2,
    18 => 0,
    19 => 1,
    20 => 1,
    21 => 0,
    22 => 0,
    _ => widget.startTab.clamp(0, 3),
  };

  @override
  void initState() {
    super.initState();
    if (widget.startTab >= 10) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.startTab == 10) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ExportScreen(
                month: DateTime(DateTime.now().year, DateTime.now().month),
              ),
            ),
          );
          return;
        }
        if (widget.startTab == 11) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PremiumScreen()),
          );
          return;
        }
        if (widget.startTab == 14 ||
            widget.startTab == 15 ||
            widget.startTab == 18) {
          final c = AppScope.of(context);
          final rec = widget.startTab == 14
              ? c.records.where((r) => r.allowance > 0).firstOrNull
              : widget.startTab == 15
              ? c.records
                    .where((r) => r.transport > 0 || r.parking > 0)
                    .firstOrNull
              : c.records
                        .where(
                          (r) =>
                              r.payType == PayType.daily &&
                              r.units != 1 &&
                              r.units != 0.5,
                        )
                        .firstOrNull ??
                    c.records
                        .where((r) => r.payType == PayType.daily)
                        .firstOrNull;
          final worker = rec == null ? null : c.workerById(rec.workerId);
          final day = rec == null ? null : tryParseDayKey(rec.day);
          if (worker != null && day != null) {
            showRecordSheet(
              context,
              worker: worker,
              day: day,
              recordId: rec!.id,
            );
          }
          return;
        }
        if (widget.startTab == 16 || widget.startTab == 20) {
          final c = AppScope.of(context);
          final month = DateTime(c.now.year, c.now.month);
          final first = c.summaryFor(month).workers.firstOrNull;
          if (first != null) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    WorkerPdfScreen(month: month, workerId: first.worker.id),
              ),
            );
          }
          return;
        }
        if (widget.startTab == 21 || widget.startTab == 22) {
          final c = AppScope.of(context);
          final day = tomorrowOf(c.now);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  PlanScreen(initialDay: day, openImage: widget.startTab == 22),
            ),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const CalendarScreen(),
          SummaryScreen(scrollToSites: widget.startTab == 19),
          RosterScreen(
            startOnSites: widget.startTab == 12 || widget.startTab == 17,
            autoEditSiteId: widget.startTab == 12
                ? 's-area'
                : widget.startTab == 17
                ? 's1'
                : null,
          ),
          SettingsScreen(scrollToToolbox: widget.startTab == 13),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          if (value == 1) {
            final controller = AppScope.of(context);
            final now = controller.now;
            ReviewPrompt.afterSummaryViewed(
              hasEntries: !controller
                  .summaryFor(DateTime(now.year, now.month))
                  .isEmpty,
            );
          }
        },
        destinations: const [
          NavigationDestination(
            key: Key('tab-calendar'),
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '出面',
          ),
          NavigationDestination(
            key: Key('tab-summary'),
            icon: Icon(Icons.summarize_outlined),
            selectedIcon: Icon(Icons.summarize),
            label: '集計',
          ),
          NavigationDestination(
            key: Key('tab-roster'),
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: '名簿',
          ),
          NavigationDestination(
            key: Key('tab-settings'),
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '設定',
          ),
        ],
      ),
    );
  }
}
