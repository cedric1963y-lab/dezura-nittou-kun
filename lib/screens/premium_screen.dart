import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../errors.dart';
import '../format.dart';
import '../plan/limits.dart';
import '../services/links.dart';
import '../state/app_controller.dart';
import '../theme.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({this.reason, super.key});

  /// Why the screen opened, shown as a short banner.
  final LimitKind? reason;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  AppController? _controller;
  var _wasPremium = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppScope.of(context);
    if (!identical(_controller, controller)) {
      _controller?.removeListener(_onChange);
      _controller = controller;
      _wasPremium = controller.premium;
      controller.addListener(_onChange);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).refreshProduct();
    });
  }

  void _onChange() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (!_wasPremium && controller.premium) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('プレミアムが有効になりました。')),
        );
    }
    _wasPremium = controller.premium;
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChange);
    super.dispose();
  }

  String? get _reasonText {
    switch (widget.reason) {
      case LimitKind.workers:
        return '無料プランで登録できる職人は${PlanLimits.freeWorkerLimit}人までです。';
      case LimitKind.sites:
        return '無料プランで登録できる現場は${PlanLimits.freeSiteLimit}か所までです。';
      case LimitKind.history:
        return '無料プランでは今月の出面と集計だけを見られます。';
      case LimitKind.export:
        return '出面表PDFとCSVの書き出しはプレミアムの機能です。';
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final pending = controller.purchasePhase == PurchasePhase.pending;
    final expires = controller.entitlement.expiresAt;
    final active = controller.entitlement.isActiveAt(controller.now);
    final reason = _reasonText;

    return Scaffold(
      appBar: AppBar(title: const Text('プレミアム')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          if (reason != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppColors.navy),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(reason, style: const TextStyle(height: 1.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          const Text(
            '人数も現場も、上限なしで集計。',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          const _Benefit(text: '職人・現場を何人でも、何か所でも登録'),
          const _Benefit(text: '先月以前の出面と集計をいつでも見返せる'),
          const _Benefit(text: '出面表PDF（A4横）を元請や事務所に送れる'),
          const _Benefit(text: 'CSVでExcelや会計ソフトに取り込める'),
          if (active && expires != null) ...[
            const SizedBox(height: 8),
            _NoteCard(
              title: 'プレミアムは有効です',
              body:
                  '${PlanLimits.planName(controller.entitlement.productId)}・${formatJapaneseDate(expires)}まで',
            ),
          ],
          const SizedBox(height: 14),
          _PlanCard(
            name: '月額プラン',
            price: controller.priceFor(PlanLimits.monthlyProductId),
            period: '/ 1か月（自動更新）',
            emphasized: true,
            child: FilledButton(
              key: const Key('buy-monthly'),
              onPressed:
                  pending || _current(controller, PlanLimits.monthlyProductId)
                  ? null
                  : () => controller.buyPlan(PlanLimits.monthlyProductId),
              child: pending
                  ? const _PendingMark()
                  : Text(
                      _current(controller, PlanLimits.monthlyProductId)
                          ? '月額を契約中'
                          : '月額ではじめる',
                    ),
            ),
          ),
          const SizedBox(height: 10),
          _PlanCard(
            name: '年額プラン',
            price: controller.priceFor(PlanLimits.yearlyProductId),
            period: '/ 1年（自動更新）',
            emphasized: false,
            child: OutlinedButton(
              key: const Key('buy-yearly'),
              onPressed:
                  pending || _current(controller, PlanLimits.yearlyProductId)
                  ? null
                  : () => controller.buyPlan(PlanLimits.yearlyProductId),
              child: Text(
                _current(controller, PlanLimits.yearlyProductId)
                    ? '年額を契約中'
                    : '年額ではじめる',
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'お支払いは購入の確定時にApple IDへ請求されます。無料体験がある場合は、その期間と終了後の料金がAppleの購入画面に表示され、無料期間が終わると課金が始まります。サブスクリプションは、現在の期間が終わる24時間以上前に解約しない限り、同じ期間・同じ価格で自動更新され、終了前の24時間以内に更新料が請求されます。管理と解約はiPhoneの「設定」> Apple ID >「サブスクリプション」から行えます。',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
          ),
          if (controller.purchaseError != null) ...[
            const SizedBox(height: 12),
            Text(
              controller.purchaseError!,
              style: const TextStyle(color: AppColors.danger, height: 1.4),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                key: const Key('restore'),
                onPressed: pending ? null : controller.restorePremium,
                child: const Text('購入を復元'),
              ),
              TextButton(
                key: const Key('link-terms'),
                onPressed: () => openExternal(AppLinks.appleEula),
                child: const Text('利用規約（EULA）'),
              ),
              TextButton(
                key: const Key('link-privacy'),
                onPressed: () => openExternal(AppLinks.privacy),
                child: const Text('プライバシーポリシー'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _NoteCard(
            title: '無料プランでできること',
            body:
                '職人${PlanLimits.freeWorkerLimit}人・現場${PlanLimits.freeSiteLimit}か所まで登録、今月の出面と集計、LINE用テキストの送信。広告はありません。解約しても、付けた出面はこのiPhoneに残ります。',
          ),
        ],
      ),
    );
  }

  bool _current(AppController controller, String productId) {
    return controller.entitlement.isActiveAt(controller.now) &&
        controller.entitlement.productId == productId;
  }
}

class _PendingMark extends StatelessWidget {
  const _PendingMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.period,
    required this.emphasized,
    required this.child,
  });

  final String name;
  final String price;
  final String period;
  final bool emphasized;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: emphasized ? AppColors.amberSoft : AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: emphasized ? AppColors.amber : AppColors.line,
          width: emphasized ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(width: 6),
              Text(period, style: const TextStyle(color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: child),
        ],
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: AppColors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(height: 1.45)),
        ],
      ),
    );
  }
}
