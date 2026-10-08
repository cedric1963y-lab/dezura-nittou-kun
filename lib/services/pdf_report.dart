import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../format.dart';
import '../logic/summary.dart';

const _navy = PdfColor.fromInt(0xFF1F3A57);
const _amber = PdfColor.fromInt(0xFFF5A300);
const _ink = PdfColor.fromInt(0xFF1B1F24);
const _muted = PdfColor.fromInt(0xFF5B6470);
const _line = PdfColor.fromInt(0xFFD5D9DE);
const _zebra = PdfColor.fromInt(0xFFF4F6F8);
const _sunday = PdfColor.fromInt(0xFFC0392B);
const _saturday = PdfColor.fromInt(0xFF2E6DB4);

/// Monthly 出面表 on A4 landscape: a worker x day grid, then totals per
/// worker and per site. The embedded font is subset to the glyphs used.
Future<Uint8List> buildMonthlyPdf({
  required ByteData fontData,
  required MonthSummary summary,
  required String title,
}) async {
  final font = pw.Font.ttf(fontData);
  final theme = pw.ThemeData.withFont(
    base: font,
    bold: font,
    italic: font,
    boldItalic: font,
  );
  final month = summary.month;
  final days = daysInMonth(month);
  final document = pw.Document(
    title: '出面表 ${formatMonth(month)}',
    author: '出面・日当くん',
    creator: '出面・日当くん',
    theme: theme,
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
      theme: theme,
      header: (context) => _header(title, month, summary),
      footer: (context) => _footer(context.pageNumber, context.pagesCount),
      build: (context) => [
        _grid(summary, days),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 5, child: _workerTable(summary)),
            pw.SizedBox(width: 16),
            pw.Expanded(flex: 4, child: _siteTable(summary)),
          ],
        ),
      ],
    ),
  );
  return document.save();
}

pw.Widget _header(String title, DateTime month, MonthSummary summary) {
  return pw.Column(
    children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: _navy,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '出面表　${formatMonth(month)}',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (title.trim().isNotEmpty)
                  pw.Text(
                    _clip(title.trim(), 40),
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
            pw.Text(
              '合計 ${formatUnits(summary.units)}人工　${formatYen(summary.amount)}',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      pw.Container(height: 3, color: _amber),
      pw.SizedBox(height: 10),
    ],
  );
}

pw.Widget _grid(MonthSummary summary, int days) {
  const nameWidth = 84.0;
  const unitsWidth = 30.0;
  const otWidth = 30.0;
  const amountWidth = 62.0;
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(nameWidth),
    for (var d = 1; d <= days; d++) d: const pw.FlexColumnWidth(),
    days + 1: const pw.FixedColumnWidth(unitsWidth),
    days + 2: const pw.FixedColumnWidth(otWidth),
    days + 3: const pw.FixedColumnWidth(amountWidth),
  };

  pw.Widget cell(
    String text, {
    PdfColor color = _ink,
    double size = 7.5,
    bool bold = false,
    pw.Alignment align = pw.Alignment.center,
    PdfColor? fill,
  }) {
    return pw.Container(
      alignment: align,
      color: fill,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  PdfColor dayColor(int day) {
    final weekday = DateTime(summary.month.year, summary.month.month, day)
        .weekday;
    if (weekday == DateTime.sunday) return _sunday;
    if (weekday == DateTime.saturday) return _saturday;
    return _ink;
  }

  final head = pw.TableRow(
    decoration: const pw.BoxDecoration(color: _zebra),
    children: [
      cell('職人', bold: true, align: pw.Alignment.centerLeft),
      for (var d = 1; d <= days; d++)
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Column(
            children: [
              pw.Text(
                '$d',
                style: pw.TextStyle(color: dayColor(d), fontSize: 7.5),
              ),
              pw.Text(
                weekdayLabel(
                  DateTime(summary.month.year, summary.month.month, d),
                ),
                style: pw.TextStyle(color: dayColor(d), fontSize: 6),
              ),
            ],
          ),
        ),
      cell('人工', bold: true),
      cell('残業', bold: true),
      cell('金額', bold: true),
    ],
  );

  final rows = <pw.TableRow>[head];
  for (var i = 0; i < summary.workers.length; i++) {
    final w = summary.workers[i];
    rows.add(
      pw.TableRow(
        decoration: i.isOdd ? const pw.BoxDecoration(color: _zebra) : null,
        children: [
          cell(
            _clip(w.worker.name, 9),
            size: 8,
            align: pw.Alignment.centerLeft,
          ),
          for (var d = 1; d <= days; d++)
            cell(
              _mark(w.unitsByDay[d]),
              size: 8,
              color: (w.unitsByDay[d] ?? 0) < 1 ? _muted : _navy,
            ),
          cell(formatUnits(w.units), bold: true),
          cell(w.overtimeHours > 0 ? formatUnits(w.overtimeHours) : '-'),
          cell(
            formatYen(w.amount),
            align: pw.Alignment.centerRight,
            bold: true,
          ),
        ],
      ),
    );
  }

  if (summary.workers.isEmpty) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(24),
      alignment: pw.Alignment.center,
      child: pw.Text(
        'この月の出面はまだありません。',
        style: const pw.TextStyle(color: _muted, fontSize: 12),
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Table(
        columnWidths: widths,
        border: pw.TableBorder.all(color: _line, width: 0.5),
        children: rows,
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        '○ = 1人工　半 = 0.5人工',
        style: const pw.TextStyle(color: _muted, fontSize: 7),
      ),
    ],
  );
}

pw.Widget _workerTable(MonthSummary summary) {
  return _table(
    title: '職人別',
    headers: const ['職人', '日数', '人工', '残業', '金額'],
    rows: [
      for (final w in summary.workers)
        [
          _clip(w.worker.name, 12),
          '${w.days}日',
          formatUnits(w.units),
          w.overtimeHours > 0 ? formatHours(w.overtimeHours) : '-',
          formatYen(w.amount),
        ],
    ],
    total: [
      '合計',
      '${summary.workingDays}日',
      formatUnits(summary.units),
      summary.overtimeHours > 0 ? formatHours(summary.overtimeHours) : '-',
      formatYen(summary.amount),
    ],
  );
}

pw.Widget _siteTable(MonthSummary summary) {
  return _table(
    title: '現場別',
    headers: const ['現場', '人数', '人工', '金額'],
    rows: [
      for (final s in summary.sites)
        [
          _clip(s.site.name, 14),
          '${s.workerCount}人',
          formatUnits(s.units),
          formatYen(s.amount),
        ],
    ],
    total: null,
  );
}

pw.Widget _table({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
  required List<String>? total,
}) {
  pw.Widget text(String value, {bool bold = false, bool right = false}) {
    return pw.Container(
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: 9,
          color: _ink,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  final last = headers.length - 1;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 11,
          color: _navy,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: _line, width: 0.5),
        columnWidths: {0: const pw.FlexColumnWidth(2.4)},
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _zebra),
            children: [
              for (var i = 0; i < headers.length; i++)
                text(headers[i], bold: true, right: i > 0),
            ],
          ),
          for (final row in rows)
            pw.TableRow(
              children: [
                for (var i = 0; i < row.length; i++)
                  text(row[i], right: i > 0, bold: i == last),
              ],
            ),
          if (total != null)
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _zebra),
              children: [
                for (var i = 0; i < total.length; i++)
                  text(total[i], bold: true, right: i > 0),
              ],
            ),
        ],
      ),
    ],
  );
}

pw.Widget _footer(int page, int pages) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.only(top: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _line, width: 0.5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          '出面・日当くんで作成',
          style: const pw.TextStyle(color: _muted, fontSize: 7),
        ),
        pw.Text(
          '$page / $pages',
          style: const pw.TextStyle(color: _muted, fontSize: 7),
        ),
      ],
    ),
  );
}

String _mark(double? units) {
  if (units == null || units <= 0) return '';
  if (units >= 1) return '○';
  return '半';
}

String _clip(String value, int max) {
  final runes = value.runes.toList();
  if (runes.length <= max) return value;
  return '${String.fromCharCodes(runes.take(max - 1))}…';
}
