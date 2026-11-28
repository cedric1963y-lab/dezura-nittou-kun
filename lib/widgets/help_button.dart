import 'package:flutter/material.dart';

import '../theme.dart';

/// 「？」: a short one-point explanation for the screen it sits on.
class HelpButton extends StatelessWidget {
  const HelpButton({required this.text, super.key});

  final HelpText text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'この画面の使い方',
      icon: const Icon(Icons.help_outline),
      onPressed: () => showHelp(context, title: text.title, body: text.body),
    );
  }
}

Future<void> showHelp(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.lightbulb_outline, color: AppColors.amber),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      content: Text(body, style: const TextStyle(height: 1.5, fontSize: 15)),
      actions: [
        TextButton(
          key: const Key('help-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    ),
  );
}

/// One-point texts, kept in one place so wording stays consistent.
class HelpText {
  const HelpText(this.title, this.body);
  final String title;
  final String body;
}

abstract final class HelpTexts {
  static const calendar = HelpText(
    '出面の画面',
    '日付を選んで職人をタップすると、出面がつきます。1回で1人工、もう1回で半日、もう1回で取消です。残業や別の現場は「…」から入れられます。',
  );
  static const summary = HelpText(
    '集計の画面',
    '今月の現場別・職人別の人工と日当です。「出力」からCSVやPDFを、LINEやメールで送れます。',
  );
  static const roster = HelpText(
    '名簿の画面',
    '職人と現場を登録する画面です。日当や現場の住所も、ここで入れておけます。',
  );
  static const settings = HelpText(
    '設定の画面',
    'プランの確認や購入の復元、使い方ガイドの再表示ができます。屋号を入れると、PDFに使われます。',
  );
}
