import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/app_controller.dart';
import '../format.dart';
import '../plan/limits.dart';
import '../services/links.dart';
import '../services/toolbox.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/help_button.dart';
import 'guide_screen.dart';
import '../widgets/restore.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({this.scrollToToolbox = false, super.key});

  /// Debug screenshot hook. Production leaves this false.
  final bool scrollToToolbox;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _toolboxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scrollToToolbox) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _toolboxKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: Duration.zero,
            alignment: 0.05,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final expires = controller.entitlement.expiresAt;
    final plan = controller.premium && expires != null
        ? 'プレミアム（${PlanLimits.planName(controller.entitlement.productId)}）・${formatJapaneseDate(expires)}まで'
        : controller.premium
        ? 'プレミアム'
        : '無料・職人 ${controller.workers.length}/${PlanLimits.freeWorkerLimit}・現場 ${controller.sites.length}/${PlanLimits.freeSiteLimit}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: const [
          HelpButton(key: Key('help-settings'), text: HelpTexts.settings),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  key: const Key('plan-tile'),
                  leading: const Icon(
                    Icons.workspace_premium_outlined,
                    color: AppColors.amber,
                  ),
                  title: const Text(
                    'プラン',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(plan),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openPremium(context),
                ),
                const Divider(height: 1),
                ListTile(
                  key: const Key('restore-settings'),
                  leading: const Icon(Icons.restore, color: AppColors.navy),
                  title: const Text(
                    '購入を復元',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('機種変更や再インストールのあとに使います。'),
                  onTap: controller.purchasePhase == PurchasePhase.pending
                      ? null
                      : () => restorePurchasesAndShowResult(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: const Key('business-name'),
              leading: const Icon(Icons.badge_outlined, color: AppColors.navy),
              title: const Text(
                'PDFに載せる屋号・名前',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                controller.businessName.isEmpty
                    ? '未設定'
                    : controller.businessName,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editBusinessName(context),
            ),
          ),
          const SizedBox(height: 10),
          Panel(
            key: _toolboxKey,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '職人の道具箱',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '同じ現場仕事のためのアプリです。',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                for (final app in ConstructionApps.others) ...[
                  const Divider(height: 1),
                  _StoreAppTile(app: app),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Panel(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: const Key('open-guide'),
              leading: const Icon(
                Icons.menu_book_outlined,
                color: AppColors.amber,
              ),
              title: const Text(
                '使い方ガイドをもう一度見る',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  fullscreenDialog: true,
                  builder: (_) => const GuideScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Panel(
            child: _Block(
              title: '使い方',
              body: '1.「名簿」で職人（自分も含む）と日当、現場を登録\n2.「出面」で日付を選び、職人をタップ（1人工 → 半日 → 取消）\n3. 残業や別の現場は「…」から\n4.「集計」で月の人工と日当を確認し、LINEやPDFで送る',
            ),
          ),
          const SizedBox(height: 10),
          const Panel(
            child: _Block(
              title: 'データの保存場所',
              body: '出面・名簿・現場はこのiPhoneの中だけに保存されます。アカウントは不要で、運営のサーバーには送りません。\n\niPhoneのバックアップをオンにしている場合、Appleのバックアップに含まれることがあります。アプリを削除すると、データも消えます。',
            ),
          ),
          const SizedBox(height: 10),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LinkTile(label: '利用規約（Apple標準EULA）', url: AppLinks.appleEula),
                const Divider(height: 1),
                _LinkTile(label: 'プライバシーポリシー', url: AppLinks.privacy),
                const Divider(height: 1),
                _LinkTile(label: 'サポート', url: AppLinks.support),
                const Divider(height: 1),
                _LinkTile(
                  label: 'サブスクリプションの管理',
                  url: AppLinks.manageSubscriptions,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Panel(
            child: _Block(
              title: 'バージョン',
              body: '${AppInfo.name} ${AppInfo.version}',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBusinessName(BuildContext context) async {
    final controller = AppScope.of(context);
    final text = TextEditingController(text: controller.businessName);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('屋号・名前'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: '例: 山田工業'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, text.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    text.dispose();
    if (value == null || !context.mounted) return;
    await guard(context, () => controller.setBusinessName(value));
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.label, required this.url});

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 20),
      onTap: () async {
        final ok = await openExternal(url);
        if (!ok && context.mounted) showSnack(context, 'ページを開けませんでした。');
      },
    );
  }
}

class _StoreAppTile extends StatelessWidget {
  const _StoreAppTile({required this.app});

  final ConstructionApp app;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('toolbox-${app.id}'),
      title: Text(app.name),
      subtitle: Text(app.blurb),
      trailing: const Icon(Icons.open_in_new, size: 20),
      onTap: () async {
        final ok = await openExternal(app.storeUrl);
        if (!ok && context.mounted) showSnack(context, 'ページを開けませんでした。');
      },
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(height: 1.5)),
      ],
    );
  }
}
