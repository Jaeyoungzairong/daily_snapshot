import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/currency_catalog.dart';
import '../data/exchange_rate_model.dart';
import '../data/exchange_rate_repository.dart';

final exchangeRateRepositoryProvider = Provider<ExchangeRateRepository>((ref) {
  return ExchangeRateRepository();
});

/// KRW 대비 최신 환율 목록 (CurrencyCatalog.targetCurrencies 전체). 한 번에 받아서
/// 카드 안에서 통화를 바꿔도 재요청 없이 즉시 전환할 수 있게 한다.
final latestRatesProvider = FutureProvider<List<CurrencyKrwRate>>((ref) async {
  final repository = ref.watch(exchangeRateRepositoryProvider);
  return repository.fetchLatestRates();
});

enum ChartPeriod {
  fourteenDays(14, '14일'),
  oneMonth(30, '1개월'),
  sixMonths(180, '6개월'),
  oneYear(365, '1년'),
  fiveYears(1825, '5년'),
  tenYears(3650, '10년');

  const ChartPeriod(this.days, this.label);

  final int days;
  final String label;
}

/// 환율 카드 전체(최신 환율 표시 + 간단 환산 + 그래프)가 공유하는, 현재 선택된 통화.
class SelectedCurrencyNotifier extends Notifier<String> {
  @override
  String build() => CurrencyCatalog.targetCurrencies.first.code;

  void select(String currencyCode) => state = currencyCode;
}

final selectedCurrencyProvider = NotifierProvider<SelectedCurrencyNotifier, String>(
  SelectedCurrencyNotifier.new,
);

class ChartPeriodNotifier extends Notifier<ChartPeriod> {
  @override
  ChartPeriod build() => ChartPeriod.fourteenDays;

  void select(ChartPeriod period) => state = period;
}

final chartPeriodProvider = NotifierProvider<ChartPeriodNotifier, ChartPeriod>(
  ChartPeriodNotifier.new,
);

/// (통화 코드, 기간)별로 캐싱되는 환율 그래프 데이터.
final chartHistoryProvider =
    FutureProvider.family<List<ExchangeRateHistoryPoint>, (String currencyCode, ChartPeriod period)>(
  (ref, args) async {
    final repository = ref.watch(exchangeRateRepositoryProvider);
    return repository.fetchRateHistory(currencyCode: args.$1, days: args.$2.days);
  },
);
