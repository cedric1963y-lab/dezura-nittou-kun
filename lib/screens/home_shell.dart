import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../services/review_prompt.dart';
import '../format.dart';
import 'calendar_screen.dart';
import 'record_sheet.dart';
import 'export_screen.dart';
import 'premium_screen.dart';
import 'roster_screen.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

/// Bottom tabs: 出面 / 集計 / 名簿 / 設定.
class HomeShell extends StatefulWidget {
  const HomeShell({this.startTab = 0, super.key});

  /// 0-3 picks a tab. Debug screenshot runs also use 10 (集計 then 出力),
  /// 11 (プレミアム), 12 (平米の現場の編集), 13 (職人の道具箱), 14 (色付け).
  final int startTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = switch (widget.startTab) {
    10 => 1,
    12 => 2,
    13 => 3,
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
        if (widget.startTab == 14) {
          final c = AppScope.of(context);
          final rec = c.records.where((r) => r.allowance > 0).firstOrNull;
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
          const SummaryScreen(),
          RosterScreen(
            startOnSites: widget.startTab == 12,
            autoEditSiteId: widget.startTab == 12 ? 's-area' : null,
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
