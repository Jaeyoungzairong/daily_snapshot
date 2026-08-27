import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import 'currency_catalog.dart';
import 'exchange_rate_model.dart';

class ExchangeRateRepository {
  ExchangeRateRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  static const String _baseUrl = 'https://api.frankfurter.dev/v1';

  /// Frankfurter를 원화(KRW) 기준으로 직접 호출하면 소수점 자리가 적어(예: 0.00072) 정밀도가 떨어진다.
  /// 대신 항상 지원되는 USD를 경유해서 KRW 대비 환율을 교차 계산한다.
  static const String _pivot = 'USD';

  Future<List<CurrencyKrwRate>> fetchLatestRates() async {
    final symbols = {
      for (final c in CurrencyCatalog.targetCurrencies) c.code,
      'KRW',
    }..remove(_pivot);

    final uri = Uri.parse('$_baseUrl/latest').replace(queryParameters: {
      'base': _pivot,
      'symbols': symbols.join(','),
    });
    final json = await _apiClient.getJson(uri);
    final rates = (json['rates'] as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, (value as num).toDouble()));

    return CurrencyKrwRate.fromPivotRates(
      pivotRates: rates,
      date: json['date'] as String,
      pivotCode: _pivot,
    );
  }

  Future<List<ExchangeRateHistoryPoint>> fetchRateHistory({
    required String currencyCode,
    required int days,
  }) async {
    final currency = CurrencyCatalog.byCode(currencyCode);
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));

    final symbols = currency.code == _pivot ? 'KRW' : '${currency.code},KRW';
    final uri = Uri.parse('$_baseUrl/${Formatters.date(start)}..${Formatters.date(end)}').replace(
      queryParameters: {'base': _pivot, 'symbols': symbols},
    );
    final json = await _apiClient.getJson(uri);

    return ExchangeRateHistoryPoint.fromPivotRatesByDate(
      ratesByDate: json['rates'] as Map<String, dynamic>,
      currency: currency,
      pivotCode: _pivot,
    );
  }
}
