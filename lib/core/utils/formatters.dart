class Formatters {
  Formatters._();

  static String temperature(double celsius) => '${celsius.round()}°C';

  static String rate(double value) {
    if (value >= 100) return value.toStringAsFixed(1);
    if (value >= 1) return value.toStringAsFixed(3);
    return value.toStringAsFixed(5);
  }

  static String amount(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    final isNegative = intPart.startsWith('-');
    final digits = isNegative ? intPart.substring(1) : intPart;
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${isNegative ? '-' : ''}$buffer.${parts[1]}';
  }

  static String date(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

  static String weekday(DateTime dateTime) => _weekdayNames[dateTime.weekday - 1];

  static String shortDate(DateTime dateTime) => '${dateTime.month}/${dateTime.day}';

  /// 월 단위 축 라벨(예: "26.2"). 연말/연초를 가로지르는 구간에서도 연도가 항상 드러나도록
  /// 월 이름 대신 pubspec 버전과 같은 축약 연도(YY) 표기를 쓴다.
  static String monthLabel(DateTime dateTime) => '${dateTime.year % 100}.${dateTime.month}';

  static String yearLabel(DateTime dateTime) => '${dateTime.year}';

  static String fullDate(DateTime dateTime) => '${dateTime.year}.${dateTime.month}.${dateTime.day}';

  static String hour24(DateTime dateTime) => '${dateTime.hour}시';
}
