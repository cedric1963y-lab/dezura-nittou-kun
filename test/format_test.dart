import 'package:dezura_nittou/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yen uses thousands separators', () {
    expect(formatYen(0), '¥0');
    expect(formatYen(18000), '¥18,000');
    expect(formatYen(1234567), '¥1,234,567');
  });

  test('units drop a trailing .0', () {
    expect(formatUnits(1), '1');
    expect(formatUnits(0.5), '0.5');
    expect(formatUnits(12.5), '12.5');
    expect(formatHours(2), '2h');
  });

  test('day keys round-trip and share the month prefix', () {
    final day = DateTime(2026, 10, 8, 23, 59);
    expect(dayKey(day), '2026-10-08');
    expect(parseDayKey('2026-10-08'), DateTime(2026, 10, 8));
    expect(dayKey(day).startsWith('${monthKey(day)}-'), isTrue);
    expect(daysInMonth(DateTime(2026, 2)), 28);
    expect(daysInMonth(DateTime(2028, 2)), 29);
    expect(addMonths(DateTime(2026, 1), -1), DateTime(2025, 12));
  });

  test('yen input accepts commas, full-width digits and 円', () {
    expect(parseYen('18,000'), 18000);
    expect(parseYen('１８０００円'), 18000);
    expect(parseYen('¥2500'), 2500);
    expect(parseYen(''), isNull);
    expect(parseYen('abc'), isNull);
  });

  test('Japanese date labels', () {
    expect(formatJapaneseDate(DateTime(2026, 10, 8)), '2026年10月8日（木）');
    expect(formatDayHeading(DateTime(2026, 10, 8)), '10月8日（木）');
    expect(exportFileName(DateTime(2026, 10), 'pdf'), '出面日当_2026年10月.pdf');
  });
}
