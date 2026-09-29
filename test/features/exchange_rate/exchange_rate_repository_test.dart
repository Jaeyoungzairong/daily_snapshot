import 'dart:convert';

import 'package:daily_snapshot/core/network/api_client.dart';
import 'package:daily_snapshot/features/exchange_rate/data/exchange_rate_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ExchangeRateRepository _repositoryReturning(Map<String, dynamic> body) {
  final client = MockClient((request) async => http.Response(jsonEncode(body), 200));
  return ExchangeRateRepository(apiClient: ApiClient(client: client));
}

void main() {
  group('ExchangeRateRepository · malformed responses', () {
    test('fetchLatestRates reports a Korean ApiException when KRW is missing', () async {
      final repository = _repositoryReturning({
        'rates': {'USD': 1.0, 'JPY': 150.0},
        'time_last_update_unix': 1780000000,
      });

      await expectLater(
        repository.fetchLatestRates(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('환율'))),
      );
    });

    test('fetchLatestRates reports a Korean ApiException when rates is not a map', () async {
      final repository = _repositoryReturning({'rates': 'oops', 'time_last_update_unix': 1});

      await expectLater(repository.fetchLatestRates(), throwsA(isA<ApiException>()));
    });

    test('fetchRateHistory reports a Korean ApiException when a day is missing KRW', () async {
      final repository = _repositoryReturning({
        'rates': {
          '2026-09-01': {'JPY': 150.0},
        },
      });

      await expectLater(
        repository.fetchRateHistory(currencyCode: 'JPY', days: 7),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('환율'))),
      );
    });
  });
}
