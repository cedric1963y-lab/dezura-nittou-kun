import 'package:flutter/material.dart';

import '../theme.dart';

/// First-launch guide: three swipeable pages, skippable.
class GuideScreen extends StatefulWidget {
  const GuideScreen({this.initialPage = 0, super.key});

  /// Debug screenshots only.
  final int initialPage;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuidePage {
  const _GuidePage(this.step, this.icon, this.title, this.body);
  final String step;
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _GuidePage(
    '1',
    Icons.groups,
    '現場と職人を登録',
    '「名簿」で、現場と職人（自分も含む）を登録します。日当もここで入れておけます。',
  ),
  _GuidePage(
    '2',
    Icons.event_available,
    '出面をつける',
    '「出面」で日付を選び、職人をタップするだけ。1人工 → 半日 → 取消と切り替わります。残業や別の現場は「…」から。',
  ),
  _GuidePage(
    '3',
    Icons.ios_share,
    '集計して送る',
    '「集計」で月の人工と日当を確認。「出力」からCSVやPDFを、LINEやメールで送れます。',
  ),
];

class _GuideScreenState extends State<GuideScreen> {
  late final _controller = PageController(initialPage: widget.initialPage);
  late var _page = widget.initialPage;

  bool get _last => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  void _next() {
    if (_last) {
      _close();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: TextButton(
                  key: const Key('guide-skip'),
                  onPressed: _close,
                  child: const Text(
                    'スキップ',
                    style: TextStyle(fontSize: 16, color: AppColors.muted),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const Key('guide-pages'),
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) => _GuideCard(_pages[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: i == _page ? 26 : 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: i == _page ? AppColors.amber : AppColors.line,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('guide-next'),
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    minimumSize: const Size.fromHeight(56),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(_last ? 'はじめる' : '次へ'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard(this.page);

  final _GuidePage page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 168,
              height: 168,
              decoration: const BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
              ),
              child: Icon(page.icon, size: 86, color: Colors.white),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'STEP ${page.step}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              page.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Text(
              page.body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
