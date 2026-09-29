import 'dart:convert';

import 'package:daily_snapshot/core/network/api_client.dart';
import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:daily_snapshot/features/weather/data/kma_weather_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _seoul = CityCandidate(name: '서울특별시', latitude: 37.563569, longitude: 126.980008);

KmaWeatherRepository _repositoryReturning(Map<String, dynamic> body) {
  final client = MockClient((request) async => http.Response(jsonEncode(body), 200));
  return KmaWeatherRepository(apiClient: ApiClient(client: client));
}

void main() {
  group('KmaWeatherRepository.fetchWeather · malformed responses', () {
    test('reports a Korean ApiException when the response envelope is missing', () async {
      final repository = _repositoryReturning({'unexpected': true});

      await expectLater(
        repository.fetchWeather(_seoul),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('날씨'))),
      );
    });

    test('keeps the KMA-provided error message when resultCode is not 00', () async {
      final repository = _repositoryReturning({
        'response': {
          'header': {'resultCode': '30', 'resultMsg': 'SERVICE KEY IS NOT REGISTERED ERROR.'},
        },
      });

      await expectLater(
        repository.fetchWeather(_seoul),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('기상청 API 오류'))),
      );
    });

    test('reports a Korean ApiException when an item is missing required fields', () async {
      final repository = _repositoryReturning({
        'response': {
          'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
          'body': {
            'items': {
              'item': [
                {'baseDate': '20260901'},
              ],
            },
          },
        },
      });

      await expectLater(
        repository.fetchWeather(_seoul),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('날씨'))),
      );
    });
  });
}
