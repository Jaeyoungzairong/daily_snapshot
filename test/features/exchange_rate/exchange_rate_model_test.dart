import 'package:daily_snapshot/features/exchange_rate/data/currency_catalog.dart';
import 'package:daily_snapshot/features/exchange_rate/data/exchange_rate_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CurrencyKrwRate.fromPivotRates', () {
    test('computes KRW rate directly for the pivot currency (USD)', () {
      final rates = CurrencyKrwRate.fromPivotRates(
        pivotRates: {'KRW': 1383.49, 'CNY': 6.7205, 'JPY': 159.07},
        date: '2026-08-26',
        pivotCode: 'USD',
      );

      final usd = rates.firstWhere((r) => r.currency.code == 'USD');
      expect(usd.krwValue, 1383.49);
      expect(usd.date, '2026-08-26');
    });

    test('cross-computes KRW rate for non-pivot currencies via the pivot', () {
      final rates = CurrencyKrwRate.fromPivotRates(
        pivotRates: {'KRW': 1383.49, 'CNY': 6.7205, 'JPY': 159.07},
        date: '2026-08-26',
        pivotCode: 'USD',
      );

      final cny = rates.firstWhere((r) => r.currency.code == 'CNY');
      expect(cny.krwValue, closeTo(1383.49 / 6.7205, 0.001));

      // JPY의 unit은 100이므로 100엔당 원화로 환산되어야 한다.
      final jpy = rates.firstWhere((r) => r.currency.code == 'JPY');
      expect(jpy.krwValue, closeTo((1383.49 / 159.07) * 100, 0.001));
    });

    test('returns one entry per CurrencyCatalog.targetCurrencies entry, in order', () {
      final rates = CurrencyKrwRate.fromPivotRates(
        pivotRates: {'KRW': 1383.49, 'CNY': 6.7205, 'JPY': 159.07},
        date: '2026-08-26',
        pivotCode: 'USD',
      );

      expect(rates.map((r) => r.currency.code).toList(),
          CurrencyCatalog.targetCurrencies.map((c) => c.code).toList());
    });
  });

  group('ExchangeRateHistoryPoint.fromPivotRatesByDate', () {
    test('cross-computes and sorts history points by date', () {
      final points = ExchangeRateHistoryPoint.fromPivotRatesByDate(
        ratesByDate: {
          '2026-08-21': {'KRW': 1384.23, 'CNY': 6.71},
          '2026-08-20': {'KRW': 1396.35, 'CNY': 6.73},
        },
        currency: const CurrencyInfo(code: 'CNY', displayName: '중국 위안'),
        pivotCode: 'USD',
      );

      expect(points, hasLength(2));
      expect(points.first.date, DateTime(2026, 8, 20));
      expect(points.first.krwValue, closeTo(1396.35 / 6.73, 0.001));
      expect(points.last.date, DateTime(2026, 8, 21));
    });

    test('uses the pivot KRW rate directly when the currency is the pivot itself', () {
      final points = ExchangeRateHistoryPoint.fromPivotRatesByDate(
        ratesByDate: {
          '2026-08-20': {'KRW': 1396.35},
        },
        currency: const CurrencyInfo(code: 'USD', displayName: '미국 달러'),
        pivotCode: 'USD',
      );

      expect(points.single.krwValue, 1396.35);
    });
  });
}
