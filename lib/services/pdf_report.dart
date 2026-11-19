import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../format.dart';
import '../logic/summary.dart';
import '../models/records.dart';

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
        if (summary.hasAllowance ||
            summary.hasTransport ||
            summary.hasParking ||
            summary.hasArea) ...[
          pw.SizedBox(height: 14),
          _payBreakdownTable(summary),
        ],
        if (_needsBreakdown(summary)) ...[
          // Own page, so the title never sits alone at the bottom of one.
          pw.NewPage(),
          _breakdownTable(summary),
        ],
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
    final weekday = DateTime(
      summary.month.year,
      summary.month.month,
      day,
    ).weekday;
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
  var stripe = 0;

  pw.TableRow workerRow(WorkerTotal w) {
    final index = stripe++;
    final contractor = w.kind == WorkerKind.contractor;
    return pw.TableRow(
      decoration: index.isOdd ? const pw.BoxDecoration(color: _zebra) : null,
      children: [
        cell(
          contractor
              ? '${_clip(w.worker.name, 6)}（外注）'
              : _clip(w.worker.name, 9),
          size: 8,
          align: pw.Alignment.centerLeft,
        ),
        for (var d = 1; d <= days; d++)
          cell(
            _mark(w.unitsByDay[d], night: w.nightDays.contains(d)),
            size: _markSize(w.unitsByDay[d], w.nightDays.contains(d)),
            color: (w.unitsByDay[d] ?? 0) < 1 ? _muted : _navy,
          ),
        cell(formatUnits(w.units), bold: true),
        cell(w.overtimeHours > 0 ? formatUnits(w.overtimeHours) : '-'),
        cell(formatYen(w.amount), align: pw.Alignment.centerRight, bold: true),
      ],
    );
  }

  pw.TableRow subtotalRow(String label, double units, double ot, int amount) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: _zebra),
      children: [
        cell(label, bold: true, size: 8, align: pw.Alignment.centerLeft),
        for (var d = 1; d <= days; d++) cell(''),
        cell(formatUnits(units), bold: true),
        cell(ot > 0 ? formatUnits(ot) : '-'),
        cell(formatYen(amount), align: pw.Alignment.centerRight, bold: true),
      ],
    );
  }

  if (summary.hasContractor) {
    // 従業員 first, then 外注, each with its own subtotal.
    for (final kind in WorkerKind.values) {
      final list = summary.workersOf(kind);
      if (list.isEmpty) continue;
      for (final w in list) {
        rows.add(workerRow(w));
      }
      rows.add(
        subtotalRow(
          '${kind.label}小計',
          summary.unitsOf(kind),
          list.fold(0.0, (sum, w) => sum + w.overtimeHours),
          summary.amountOf(kind),
        ),
      );
    }
    rows.add(
      subtotalRow('合計', summary.units, summary.overtimeHours, summary.amount),
    );
  } else {
    for (final w in summary.workers) {
      rows.add(workerRow(w));
    }
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
        '○ = 1人工　半 = 0.5人工　数字 = 1・0.5以外の人工（1.1など、または同日の合計）　夜 = 夜勤を含む日',
        style: const pw.TextStyle(color: _muted, fontSize: 7),
      ),
    ],
  );
}

pw.Widget _workerTable(MonthSummary summary) {
  List<String> row(WorkerTotal w) => [
    w.kind == WorkerKind.contractor
        ? '${_clip(w.worker.name, 7)}（外注）'
        : _clip(w.worker.name, 10),
    w.payName,
    '${w.days}日',
    formatUnits(w.units),
    w.payType == PayType.hourly ? formatHours(w.hours) : '-',
    w.overtimeHours > 0 ? formatHours(w.overtimeHours) : '-',
    formatYen(w.amount),
  ];

  final rows = <List<String>>[];
  final bold = <int>{};
  if (summary.hasContractor) {
    for (final kind in WorkerKind.values) {
      final list = summary.workersOf(kind);
      if (list.isEmpty) continue;
      rows.addAll(list.map(row));
      bold.add(rows.length);
      rows.add([
        '${kind.label}小計',
        '',
        '${summary.daysOf(kind)}日',
        formatUnits(summary.unitsOf(kind)),
        '',
        _otOf(list),
        formatYen(summary.amountOf(kind)),
      ]);
    }
  } else {
    rows.addAll(summary.workers.map(row));
  }
  return _table(
    title: summary.hasContractor ? '従業員・外注別' : '職人別',
    headers: const ['職人', '区分', '日数', '人工', '時間', '残業', '金額'],
    rows: rows,
    boldRows: bold,
    total: [
      '合計',
      '',
      '${summary.workingDays}日',
      formatUnits(summary.units),
      '',
      summary.overtimeHours > 0 ? formatHours(summary.overtimeHours) : '-',
      formatYen(summary.amount),
    ],
  );
}

pw.Widget _payBreakdownTable(MonthSummary summary) {
  final wageLabel = summary.hasMonthly ? '日当・給与' : '日当';
  List<String> row(WorkerTotal w) => [
    w.kind == WorkerKind.contractor
        ? '${_clip(w.worker.name, 7)}（外注）'
        : _clip(w.worker.name, 10),
    formatYen(w.wageAmount + w.salary),
    if (summary.hasAllowance) w.allowance > 0 ? formatYen(w.allowance) : '-',
    if (summary.hasTransport) w.transport > 0 ? formatYen(w.transport) : '-',
    if (summary.hasParking) w.parking > 0 ? formatYen(w.parking) : '-',
    if (summary.hasArea) w.areaAmount > 0 ? formatYen(w.areaAmount) : '-',
    formatYen(w.amount),
  ];
  return _table(
    title: '金額の内訳',
    headers: [
      '職人',
      wageLabel,
      if (summary.hasAllowance) '色付け',
      if (summary.hasTransport) '交通費',
      if (summary.hasParking) '駐車場代',
      if (summary.hasArea) '平米割り',
      '合計',
    ],
    rows: [for (final w in summary.workers) row(w)],
    total: [
      '合計',
      formatYen(summary.wageTotal + summary.salaryTotal),
      if (summary.hasAllowance) formatYen(summary.allowanceTotal),
      if (summary.hasTransport) formatYen(summary.transportTotal),
      if (summary.hasParking) formatYen(summary.parkingTotal),
      if (summary.hasArea) formatYen(summary.areaTotal),
      formatYen(summary.amount),
    ],
    note: summary.hasArea ? areaSiteNote : null,
  );
}

String _otOf(List<WorkerTotal> list) {
  final ot = list.fold(0.0, (sum, w) => sum + w.overtimeHours);
  return ot > 0 ? formatHours(ot) : '-';
}

/// True when someone was split over several 現場 or has a 夜勤 entry.
bool _needsBreakdown(MonthSummary summary) {
  return summary.workers.any(
    (w) => w.breakdown.length > 1 || w.nightDays.isNotEmpty,
  );
}

pw.Widget _breakdownTable(MonthSummary summary) {
  return _table(
    title: '現場・昼夜別の内訳',
    headers: const ['職人', '現場', '昼夜', '日数', '人工', '金額'],
    rows: [
      for (final w in summary.workers)
        for (final b in w.breakdown)
          [
            w.kind == WorkerKind.contractor
                ? '${_clip(w.worker.name, 7)}（外注）'
                : _clip(w.worker.name, 10),
            _siteCell(b.site),
            b.shift.label,
            '${b.days}日',
            formatUnits(b.units),
            formatYen(b.amount),
          ],
    ],
    total: null,
    note: summary.hasMonthly ? monthlySiteNote : null,
  );
}

pw.Widget _siteTable(MonthSummary summary) {
  final table = _table(
    title: '現場別',
    headers: const ['現場', '人数', '人工', '金額'],
    rows: [
      for (final s in summary.sites)
        [
          _siteCell(s.site, areaSuffix: true),
          '${s.workerCount}人',
          formatUnits(s.units),
          formatYen(s.amount),
        ],
    ],
    total: null,
  );
  final notes = [
    if (summary.hasMonthly) monthlySiteNote,
    if (summary.hasArea) areaSiteNote,
  ];
  if (notes.isEmpty) return table;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      table,
      pw.SizedBox(height: 4),
      pw.Text(
        notes.join('\n'),
        style: const pw.TextStyle(color: _muted, fontSize: 7),
      ),
    ],
  );
}

pw.Widget _table({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
  required List<String>? total,
  Set<int> boldRows = const {},
  String? note,
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
          for (var r = 0; r < rows.length; r++)
            pw.TableRow(
              decoration: boldRows.contains(r)
                  ? const pw.BoxDecoration(color: _zebra)
                  : null,
              children: [
                for (var i = 0; i < rows[r].length; i++)
                  text(
                    rows[r][i],
                    right: i > 0,
                    bold: i == last || boldRows.contains(r),
                  ),
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
      if (note != null) ...[
        pw.SizedBox(height: 4),
        pw.Text(note, style: const pw.TextStyle(color: _muted, fontSize: 7)),
      ],
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

/// One cell of the grid. A single 1 or 0.5 shows ○ / 半; other 人工
/// (1.1, a crew, or several entries) show the day's total.
String _mark(double? units, {bool night = false}) =>
    attendanceMark(units, night: night);

double _markSize(double? units, bool night) {
  final longText = (units ?? 0) > 0 && (night || (units ?? 0) >= 10);
  return longText ? 6.5 : 8;
}

String _clip(String value, int max) {
  final runes = value.runes.toList();
  if (runes.length <= max) return value;
  return '${String.fromCharCodes(runes.take(max - 1))}…';
}

/// Site name, plus the address on a second line when it is set.
String _siteCell(Site site, {bool areaSuffix = false, int nameMax = 16}) {
  final name = areaSuffix && site.isAreaSite ? '${site.name}（平米）' : site.name;
  final head = _clip(name, nameMax);
  final address = site.address.trim();
  if (address.isEmpty) return head;
  return '$head\n${_clip(address, 22)}';
}

/// Personal 出面明細 for one worker only (portrait A4). No other workers.
Future<Uint8List> buildWorkerMonthlyPdf({
  required ByteData fontData,
  required MonthSummary summary,
  required WorkerTotal worker,
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
  final lines = workerDayLines(summary, worker.worker.id);
  final showAllowance = worker.allowance > 0;
  final showTransport = worker.transport > 0;
  final showParking = worker.parking > 0;
  final document = pw.Document(
    title: '${worker.worker.name} ${formatMonth(month)}の出面',
    author: '出面・日当くん',
    creator: '出面・日当くん',
    theme: theme,
  );

  List<String> headers() => [
    '日付',
    '現場',
    '昼夜',
    '人工',
    '日当',
    if (showAllowance) '色付け',
    if (showTransport) '交通費',
    if (showParking) '駐車場代',
    '金額',
  ];

  List<String> dayRow(WorkerDayLine line) => [
    line.record.day,
    line.site == null ? '' : _siteCell(line.site!),
    line.record.shift.label,
    formatUnits(line.record.units),
    line.wage > 0 ? formatYen(line.wage) : '-',
    if (showAllowance) line.allowance > 0 ? formatYen(line.allowance) : '-',
    if (showTransport) line.transport > 0 ? formatYen(line.transport) : '-',
    if (showParking) line.parking > 0 ? formatYen(line.parking) : '-',
    formatYen(line.amount),
  ];

  List<String> extraRow(String label, int yen) => [
    monthKey(month),
    label,
    '',
    '',
    '',
    if (showAllowance) '',
    if (showTransport) '',
    if (showParking) '',
    formatYen(yen),
  ];

  final rows = [for (final line in lines) dayRow(line)];
  if (worker.salary > 0) rows.add(extraRow('月給', worker.salary));
  if (worker.areaAmount > 0) rows.add(extraRow('平米割り', worker.areaAmount));

  final kind = worker.kind == WorkerKind.contractor
      ? '${worker.worker.name}（外注）'
      : worker.worker.name;

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
      theme: theme,
      footer: (context) => _footer(context.pageNumber, context.pagesCount),
      build: (context) => [
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
                    '個人明細　${formatMonth(month)}',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    kind,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 12,
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
                '合計 ${formatYen(worker.amount)}',
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
        pw.SizedBox(height: 12),
        if (rows.isEmpty)
          pw.Text(
            'この月の出面はまだありません。',
            style: const pw.TextStyle(color: _muted, fontSize: 11),
          )
        else
          _table(
            title: '出面',
            headers: headers(),
            rows: rows,
            total: [
              '合計',
              '${worker.days}日',
              '',
              formatUnits(worker.units),
              formatYen(worker.wageAmount),
              if (showAllowance) formatYen(worker.allowance),
              if (showTransport) formatYen(worker.transport),
              if (showParking) formatYen(worker.parking),
              formatYen(worker.amount),
            ],
          ),
        pw.SizedBox(height: 10),
        pw.Text(
          'この明細は${worker.worker.name}さんのみです。他の職人のデータは含みません。',
          style: const pw.TextStyle(color: _muted, fontSize: 8),
        ),
        if (worker.areaAmount > 0) ...[
          pw.SizedBox(height: 4),
          pw.Text(
            areaSiteNote,
            style: const pw.TextStyle(color: _muted, fontSize: 7),
          ),
        ],
      ],
    ),
  );
  return document.save();
}
