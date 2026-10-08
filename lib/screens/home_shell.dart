import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'export_screen.dart';
import 'premium_screen.dart';
import 'roster_screen.dart';
import 'settings_screen.dart';
import 'summary_screen.dart';

/// Bottom tabs: 出面 / 集計 / 名簿 / 設定.
class HomeShell extends StatefulWidget {
  const HomeShell({this.startTab = 0, super.key});

  /// 0-3 picks a tab. Debug screenshot runs also use 10 (集計 then 出力)
  /// and 11 (プレミアム).
  final int startTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.startTab == 10 ? 1 : widget.startTab.clamp(0, 3);

  @override
  void initState() {
    super.initState();
    if (widget.startTab >= 10) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final page = widget.startTab == 10
            ? ExportScreen(month: DateTime(DateTime.now().year, DateTime.now().month))
            : const PremiumScreen();
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          CalendarScreen(),
          SummaryScreen(),
          RosterScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
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
