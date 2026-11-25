import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/app_controller.dart';

/// Runs the existing restore flow and shows a clear Japanese result.
Future<void> restorePurchasesAndShowResult(BuildContext context) async {
  final controller = AppScope.of(context);
  final result = await controller.restorePremium();
  if (!context.mounted) return;

  late final String title;
  String? body;
  switch (result) {
    case RestoreResult.restored:
      title = '購入を復元しました。';
      body = 'プレミアムが有効です。';
    case RestoreResult.nothingToRestore:
      title = '復元できる購入はありませんでした。';
      body = '契約したApple IDでサインインしているか確認してください。';
    case RestoreResult.failed:
      title = '復元できませんでした。';
      body = controller.purchaseError;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('restore-result'),
      title: Text(title),
      content: body == null || body.isEmpty
          ? null
          : Text(body, style: const TextStyle(height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
