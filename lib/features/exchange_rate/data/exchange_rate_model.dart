import 'currency_catalog.dart';

/// 특정 통화의 "현재" 원화 환율. [krwValue]는 이미 [currency.unit] 단위로 환산되어 있다.
/// 예: JPY는 unit=100이므로 krwValue는 "100엔당 원화" 값이다.
class CurrencyKrwRate {
  const CurrencyKrwRate({
    required this.currency,
    required this.krwValue,
    required this.date,
  });

  final CurrencyInfo currency;
  final double krwValue;
  final String date;

  /// Frankfurter의 `base=[pivotCode]` 응답 rates 맵(KRW 포함)에서
  /// CurrencyCatalog.targetCurrencies 전체의 KRW 대비 환율을 교차 계산한다.
  static List<CurrencyKrwRate> fromPivotRates({
    required Map<String, double> pivotRates,
    required String date,
    required String pivotCode,
  }) {
    final krwPerPivot = pivotRates['KRW']!;
    return CurrencyCatalog.targetCurrencies.map((currency) {
      final krwPerUnit = currency.code == pivotCode ? krwPerPivot : krwPerPivot / pivotRates[currency.code]!;
      return CurrencyKrwRate(
        currency: currency,
        krwValue: krwPerUnit * currency.unit,
        date: date,
      );
    }).toList();
  }
}

/// 그래프용 시계열 한 점. krwValue는 [CurrencyKrwRate]와 동일하게 unit 환산이 끝난 값이다.
class ExchangeRateHistoryPoint {
  const ExchangeRateHistoryPoint({
    required this.date,
    required this.krwValue,
  });

  final DateTime date;
  final double krwValue;

  /// Frankfurter time-series 응답의 `rates` 맵(날짜별 rates 객체)에서
  /// 특정 통화의 날짜별 KRW 대비 환율을 교차 계산해 날짜순으로 정렬해 반환한다.
  static List<ExchangeRateHistoryPoint> fromPivotRatesByDate({
    required Map<String, dynamic> ratesByDate,
    required CurrencyInfo currency,
    required String pivotCode,
  }) {
    final points = ratesByDate.entries.map((entry) {
      final dayRates = (entry.value as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, (value as num).toDouble()));
      final krwPerPivot = dayRates['KRW']!;
      final krwPerUnit = currency.code == pivotCode ? krwPerPivot : krwPerPivot / dayRates[currency.code]!;
      return ExchangeRateHistoryPoint(
        date: DateTime.parse(entry.key),
        krwValue: krwPerUnit * currency.unit,
      );
    }).toList();

    points.sort((a, b) => a.date.compareTo(b.date));
    return points;
  }
}
