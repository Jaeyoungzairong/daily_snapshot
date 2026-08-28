import 'package:daily_snapshot/features/weather/data/kma_base_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KmaBaseTime.ultraSrtNcst', () {
    test('uses the current hour once past the 40-minute confirmation mark', () {
      final result = KmaBaseTime.ultraSrtNcst(DateTime(2026, 8, 28, 10, 45));
      expect(result.baseDate, '20260828');
      expect(result.baseTime, '1000');
    });

    test('falls back to the previous hour before the 40-minute mark', () {
      final result = KmaBaseTime.ultraSrtNcst(DateTime(2026, 8, 28, 10, 5));
      expect(result.baseDate, '20260828');
      expect(result.baseTime, '0900');
    });

    test('rolls back across a day boundary just after midnight', () {
      final result = KmaBaseTime.ultraSrtNcst(DateTime(2026, 8, 28, 0, 5));
      expect(result.baseDate, '20260827');
      expect(result.baseTime, '2300');
    });
  });

  group('KmaBaseTime.vilageFcst', () {
    test('picks the most recent slot once the 10-minute publish delay has passed', () {
      final result = KmaBaseTime.vilageFcst(DateTime(2026, 8, 28, 10, 1));
      expect(result.baseDate, '20260828');
      expect(result.baseTime, '0800');
    });

    test('stays on the previous slot until the publish delay has passed', () {
      final result = KmaBaseTime.vilageFcst(DateTime(2026, 8, 28, 8, 5));
      expect(result.baseDate, '20260828');
      expect(result.baseTime, '0500');
    });

    test('falls back to the previous day 23:00 slot before today\'s first (02:00) slot publishes', () {
      final result = KmaBaseTime.vilageFcst(DateTime(2026, 8, 28, 1, 30));
      expect(result.baseDate, '20260827');
      expect(result.baseTime, '2300');
    });
  });
}
