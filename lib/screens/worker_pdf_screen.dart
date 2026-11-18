import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app_scope.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/dialogs.dart';

/// Preview of one worker's monthly 出面 PDF. Used by screenshot runs
/// and as a way to confirm the share file before sending.
class WorkerPdfScreen extends StatefulWidget {
  const WorkerPdfScreen({
    required this.month,
    required this.workerId,
    super.key,
  });

  final DateTime month;
  final String workerId;

  @override
  State<WorkerPdfScreen> createState() => _WorkerPdfScreenState();
}

class _WorkerPdfScreenState extends State<WorkerPdfScreen> {
  Future<Uint8List?>? _preview;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _preview ??= _renderPreview();
  }

  Future<Uint8List?> _renderPreview() async {
    final controller = AppScope.of(context);
    try {
      final pdf = await controller.pdfBytesForWorker(
        widget.month,
        widget.workerId,
      );
      await for (final page in Printing.raster(pdf, pages: const [0], dpi: 144)) {
        return await page.toPng();
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final name = controller.workerById(widget.workerId)?.name ?? '職人';
    return Scaffold(
      appBar: AppBar(title: Text('$name ${formatMonth(widget.month)}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          const Text(
            '個人明細PDF',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: 210 / 297,
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
        ],
      ),
    );
  }
}
