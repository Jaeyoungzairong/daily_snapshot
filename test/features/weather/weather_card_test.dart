import 'package:daily_snapshot/features/weather/application/weather_provider.dart';
import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:daily_snapshot/features/weather/data/weather_model.dart';
import 'package:daily_snapshot/features/weather/data/weather_repository.dart';
import 'package:daily_snapshot/features/weather/presentation/weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 강수확률/강수량이 모든 슬롯에 존재하는(가장 긴) 경우를 가정한 가짜 리포지토리.
/// 시간별/주간 예보 칸의 레이아웃이 이 최악의 경우에도 넘치지 않는지 검증하는 용도.
class _FakeWeatherRepository extends WeatherRepository {
  @override
  Future<WeatherModel> fetchWeather(CityCandidate city) async {
    return WeatherModel(
      cityName: city.displayLabel,
      currentTemp: 20,
      condition: WeatherCondition.rain,
      windSpeed: 5,
      maxTemp: 25,
      minTemp: 15,
      precipitationAmount: '1.0mm',
      dailyForecast: List.generate(3, (i) {
        return DailyForecast(
          date: DateTime(2026, 8, 27 + i),
          maxTemp: 25,
          minTemp: 15,
          condition: WeatherCondition.rain,
          precipitationProbability: 80,
        );
      }),
      hourlyForecast: List.generate(24, (i) {
        return HourlyForecast(
          time: DateTime(2026, 8, 27, i),
          temperature: 20,
          condition: WeatherCondition.rain,
          isNow: i == 0,
          precipitationProbability: 80,
          precipitationAmount: '30.0~50.0mm',
        );
      }),
    );
  }

  @override
  Future<List<CityCandidate>> searchCities(String query) async => [];
}

void main() {
  testWidgets('WeatherCard renders without overflow when every slot has precipitation data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository())],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WeatherCard()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
