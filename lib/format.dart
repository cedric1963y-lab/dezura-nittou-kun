const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

/// Calendar day as `YYYY-MM-DD`. Records are keyed by this string so that a
/// time zone change on the phone never moves a record to another day.
String dayKey(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTime parseDayKey(String key) {
  final parts = key.split('-');
  if (parts.length != 3) throw FormatException('日付の形式が不正です: $key');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// `YYYY-MM` prefix shared by every [dayKey] in that month.
String monthKey(DateTime month) {
  final y = month.year.toString().padLeft(4, '0');
  final m = month.month.toString().padLeft(2, '0');
  return '$y-$m';
}

DateTime firstOfMonth(DateTime value) => DateTime(value.year, value.month);

DateTime addMonths(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta);

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

String weekdayLabel(DateTime value) => _weekdays[value.weekday - 1];

String formatMonth(DateTime month) => '${month.year}年${month.month}月';

String formatJapaneseDate(DateTime value) {
  return '${value.year}年${value.month}月${value.day}日（${weekdayLabel(value)}）';
}

String formatDayHeading(DateTime value) {
  return '${value.month}月${value.day}日（${weekdayLabel(value)}）';
}

String formatShortDate(DateTime value) {
  return '${value.month}/${value.day}（${weekdayLabel(value)}）';
}

/// 18000 -> `¥18,000`.
String formatYen(int yen) {
  final negative = yen < 0;
  final digits = yen.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}¥$buffer';
}

/// 1.0 -> `1`, 0.5 -> `0.5`, 12.5 -> `12.5`.
String formatUnits(double units) {
  final rounded = (units * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1);
}

String formatHours(double hours) => '${formatUnits(hours)}h';

String collapseWhitespace(String input) {
  return input.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// File name safe for the share sheet, for example `出面_2026年10月.pdf`.
String exportFileName(DateTime month, String extension) {
  final m = month.month.toString().padLeft(2, '0');
  return '出面日当_${month.year}年$m月.$extension';
}

/// Parses `18,000` / `１８０００` / `18000円` into yen. Null when empty.
int? parseYen(String input) {
  final normalized = input
      .replaceAllMapped(
        RegExp('[０-９]'),
        (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0xFEE0),
      )
      .replaceAll(RegExp(r'[,，円¥￥\s]'), '');
  if (normalized.isEmpty) return null;
  return int.tryParse(normalized);
}
