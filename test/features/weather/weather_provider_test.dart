import 'package:daily_snapshot/features/weather/application/weather_provider.dart';
import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:daily_snapshot/features/weather/data/weather_model.dart';
import 'package:daily_snapshot/features/weather/data/weather_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWeatherRepository extends WeatherRepository {
  @override
  Future<WeatherModel> fetchWeather(CityCandidate city) async {
    return WeatherModel(
      cityName: city.displayLabel,
      currentTemp: 20,
      weatherCode: 0,
      windSpeed: 5,
      maxTemp: 25,
      minTemp: 15,
      dailyForecast: [
        DailyForecast(date: DateTime(2026, 8, 27), maxTemp: 25, minTemp: 15, weatherCode: 0),
      ],
      hourlyForecast: [
        HourlyForecast(time: DateTime(2026, 8, 27, 14), temperature: 20, weatherCode: 0, isNow: true),
      ],
    );
  }

  @override
  Future<List<CityCandidate>> searchCities(String query) async {
    return [
      CityCandidate(name: query, latitude: 0, longitude: 0, country: '테스트국가'),
    ];
  }
}

void main() {
  const seoul = CityCandidate(
    name: 'Seoul',
    latitude: 37.5665,
    longitude: 126.9780,
    country: '대한민국',
  );

  test('weatherProvider exposes data from the repository', () async {
    final container = ProviderContainer(
      overrides: [
        weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository()),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(weatherProvider(seoul).future);

    expect(result.cityName, seoul.displayLabel);
    expect(result.currentTemp, 20);
    expect(result.description, '맑음');
  });

  test('citySearchProvider returns candidates for a non-empty query', () async {
    final container = ProviderContainer(
      overrides: [
        weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository()),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(citySearchProvider('Anyang').future);

    expect(result, hasLength(1));
    expect(result.first.name, 'Anyang');
  });

  test('citySearchProvider returns empty list for blank query', () async {
    final container = ProviderContainer(
      overrides: [
        weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository()),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(citySearchProvider('   ').future);

    expect(result, isEmpty);
  });
}
