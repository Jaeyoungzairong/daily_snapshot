import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import 'currency_catalog.dart';
import 'exchange_rate_model.dart';

class ExchangeRateRepository {
  ExchangeRateRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  static const String _historyBaseUrl = 'https://api.frankfurter.dev/v1';

  /// Frankfurter(ECB 기준환율)는 영업일에만 갱신되어 주말/공휴일에는 기준일이 며칠씩
  /// 뒤처진다. "최신 환율" 표시만 open.er-api.com(키 불필요, 매일 갱신)으로 받아오고,
  /// 과거 시계열(그래프)은 open.er-api.com이 지원하지 않으므로 Frankfurter를 그대로 쓴다.
  static final Uri _latestUri = Uri.parse('https://open.er-api.com/v6/latest/USD');

  /// Frankfurter를 원화(KRW) 기준으로 직접 호출하면 소수점 자리가 적어(예: 0.00072) 정밀도가 떨어진다.
  /// 대신 항상 지원되는 USD를 경유해서 KRW 대비 환율을 교차 계산한다.
  static const String _pivot = 'USD';

  Future<List<CurrencyKrwRate>> fetchLatestRates() async {
    final json = await _apiClient.getJson(_latestUri);
    final rates = (json['rates'] as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, (value as num).toDouble()));
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      (json['time_last_update_unix'] as num).toInt() * 1000,
      isUtc: true,
    );

    return CurrencyKrwRate.fromPivotRates(
      pivotRates: rates,
      date: Formatters.date(updatedAt),
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
    final uri = Uri.parse('$_historyBaseUrl/${Formatters.date(start)}..${Formatters.date(end)}').replace(
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
