import 'package:daily_snapshot/core/network/api_client.dart';
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
      condition: WeatherCondition.clear,
      windSpeed: 5,
      maxTemp: 25,
      minTemp: 15,
      dailyForecast: [
        DailyForecast(
          date: DateTime(2026, 8, 27),
          maxTemp: 25,
          minTemp: 15,
          condition: WeatherCondition.clear,
          precipitationProbability: 10,
        ),
      ],
      hourlyForecast: [
        HourlyForecast(
          time: DateTime(2026, 8, 27, 14),
          temperature: 20,
          condition: WeatherCondition.clear,
          isNow: true,
          precipitationProbability: 10,
          precipitationAmount: null,
        ),
      ],
      precipitationAmount: null,
    );
  }

  @override
  Future<List<CityCandidate>> searchCities(String query) async {
    return [CityCandidate(name: query, latitude: 0, longitude: 0, country: '테스트국가')];
  }

  @override
  Future<CityCandidate?> nearestCity(double latitude, double longitude) async => null;
}

/// 날씨 조회가 항상 [error]로 실패하는 저장소. 호출 횟수를 세어 자동 재시도 여부를 확인한다.
class _FailingWeatherRepository extends _FakeWeatherRepository {
  _FailingWeatherRepository(this.error);

  final Object error;
  int calls = 0;

  @override
  Future<WeatherModel> fetchWeather(CityCandidate city) async {
    calls++;
    throw error;
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
      overrides: [weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository())],
    );
    addTearDown(container.dispose);

    final result = await container.read(weatherProvider(seoul).future);

    expect(result.cityName, seoul.displayLabel);
    expect(result.currentTemp, 20);
    expect(result.description, '맑음');
  });

  test('weatherProvider shows an ApiException as an error right away, without auto-retry', () async {
    final repository = _FailingWeatherRepository(ApiException('서버 응답이 없습니다.'));
    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(weatherProvider(seoul), (_, _) {});

    await expectLater(container.read(weatherProvider(seoul).future), throwsA(isA<ApiException>()));
    // Riverpod 기본 정책이었다면 이 시간 동안 재시도하며 상태가 로딩으로 남는다.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final state = container.read(weatherProvider(seoul));
    expect(state.isLoading, isFalse);
    expect(state.hasError, isTrue);
    expect(repository.calls, 1);
  });

  test('weatherProvider still auto-retries other exceptions (Riverpod default)', () async {
    final repository = _FailingWeatherRepository(Exception('unexpected'));
    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.listen(weatherProvider(seoul), (_, _) {});

    // 기본 정책의 첫 재시도는 200ms, 두 번째는 400ms 뒤다.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(repository.calls, greaterThan(1));
  });

  test('citySearchProvider returns candidates for a non-empty query', () async {
    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository())],
    );
    addTearDown(container.dispose);

    final result = await container.read(citySearchProvider('Anyang').future);

    expect(result, hasLength(1));
    expect(result.first.name, 'Anyang');
  });

  test('citySearchProvider returns empty list for blank query', () async {
    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(_FakeWeatherRepository())],
    );
    addTearDown(container.dispose);

    final result = await container.read(citySearchProvider('   ').future);

    expect(result, isEmpty);
  });
}
