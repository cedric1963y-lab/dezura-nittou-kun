import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app_scope.dart';
import '../errors.dart';
import '../format.dart';
import '../services/share_service.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

/// Monthly 出面表 PDF preview, CSV and LINE text.
class ExportScreen extends StatefulWidget {
  const ExportScreen({required this.month, super.key});

  final DateTime month;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  Future<Uint8List?>? _preview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preview ??= _renderPreview();
  }

  Future<Uint8List?> _renderPreview() async {
    final controller = AppScope.of(context);
    try {
      final pdf = await controller.pdfBytesFor(widget.month);
      await for (final page in Printing.raster(pdf, pages: const [0], dpi: 144)) {
        return await page.toPng();
      }
    } catch (_) {
      // The buttons below still work without the preview.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final premium = controller.premium;
    final open = controller.canOpenMonth(widget.month);
    final text = open ? controller.textFor(widget.month) : '';

    return Scaffold(
      appBar: AppBar(title: Text('${formatMonth(widget.month)}の出力')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          const Text(
            '出面表PDF（A4横）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: 297 / 210,
              child: FutureBuilder<Uint8List?>(
                future: _preview,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final png = snapshot.data;
                  if (png == null) {
                    return const Center(
                      child: Text(
                        'プレビューを表示できませんでした',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    );
                  }
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Image.memory(png, fit: BoxFit.contain),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (buttonContext) => FilledButton.icon(
                    key: const Key('share-pdf'),
                    onPressed: () => guard(context, () async {
                      final origin = shareOriginOf(buttonContext);
                      final path = await controller.exportPdf(widget.month);
                      await shareFile(
                        path: path,
                        fileName: exportFileName(widget.month, 'pdf'),
                        mimeType: 'application/pdf',
                        subject: '出面表 ${formatMonth(widget.month)}',
                        origin: origin,
                      );
                    }),
                    icon: Icon(premium ? Icons.ios_share : Icons.lock_outline),
                    label: const Text('PDFを送る'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Builder(
                  builder: (buttonContext) => OutlinedButton.icon(
                    key: const Key('share-csv'),
                    onPressed: () => guard(context, () async {
                      final origin = shareOriginOf(buttonContext);
                      final path = await controller.exportCsv(widget.month);
                      await shareFile(
                        path: path,
                        fileName: exportFileName(widget.month, 'csv'),
                        mimeType: 'text/csv',
                        subject: '出面 ${formatMonth(widget.month)}',
                        origin: origin,
                      );
                    }),
                    icon: Icon(premium ? Icons.table_view : Icons.lock_outline),
                    label: const Text('CSV'),
                  ),
                ),
              ),
            ],
          ),
          if (!premium)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton(
                onPressed: () => openPremium(context, reason: LimitKind.export),
                child: const Text('PDF・CSVの書き出しはプレミアムで使えます'),
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'LINE用テキスト（無料）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Panel(
            child: SelectableText(
              text,
              key: const Key('line-text'),
              style: const TextStyle(fontSize: 14, height: 1.55),
            ),
          ),
          const SizedBox(height: 12),
          Builder(
            builder: (buttonContext) => FilledButton.icon(
              onPressed: () => guard(
                context,
                () => shareText(
                  text,
                  subject: '出面・日当 ${formatMonth(widget.month)}',
                  origin: shareOriginOf(buttonContext),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('テキストを送る'),
            ),
          ),
        ],
      ),
    );
  }
}
