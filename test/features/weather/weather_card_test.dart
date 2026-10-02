import 'package:daily_snapshot/core/network/api_client.dart';
import 'package:daily_snapshot/features/weather/application/weather_provider.dart';
import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:daily_snapshot/features/weather/data/weather_model.dart';
import 'package:daily_snapshot/features/weather/data/weather_repository.dart';
import 'package:daily_snapshot/features/weather/presentation/weather_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 강수확률/강수량이 모든 슬롯에 존재하는(가장 긴) 경우를 가정한 가짜 리포지토리.
/// 시간별/주간 예보 칸의 레이아웃이 이 최악의 경우에도 넘치지 않는지 검증하는 용도이고,
/// 자동 갱신 테스트를 위해 조회 횟수·지연·실패도 제어할 수 있다.
class _FakeWeatherRepository extends WeatherRepository {
  _FakeWeatherRepository({this.delay = Duration.zero, this.age = Duration.zero});

  final Duration delay;

  /// 돌려주는 데이터의 조회 시각을 "지금보다 이만큼 전"으로 만든다(복귀 시 갱신 판단 테스트용).
  Duration age;
  int fetchCount = 0;
  bool failing = false;

  @override
  Future<WeatherModel> fetchWeather(CityCandidate city) async {
    fetchCount++;
    final callNumber = fetchCount;
    await Future<void>.delayed(delay);
    if (failing) throw ApiException('서버 응답이 없습니다.');
    return WeatherModel(
      cityName: city.displayLabel,
      currentTemp: 20,
      condition: WeatherCondition.rain,
      windSpeed: 5,
      maxTemp: 25,
      minTemp: 15,
      precipitationAmount: '1.0mm',
      // 조회 횟수를 분(minute)에 넣어, 화면의 "HH:mm 기준"으로 몇 번째 조회 결과인지 알 수 있게 한다.
      fetchedAt: age == Duration.zero
          ? DateTime(2026, 9, 30, 9, callNumber)
          : DateTime.now().subtract(age),
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

  @override
  Future<CityCandidate?> nearestCity(double latitude, double longitude) async => null;
}

Future<void> _pumpCard(WidgetTester tester, _FakeWeatherRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [weatherRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: WeatherCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 앱이 백그라운드로 갔다가 다시 보이게 된 상황.
Future<void> _backgroundThenResume(WidgetTester tester) async {
  // 프레임워크가 허용하는 전이 순서(resumed → inactive → hidden → paused → 되돌아옴)를 따른다.
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

void main() {
  testWidgets('WeatherCard renders without overflow when every slot has precipitation data', (
    tester,
  ) async {
    await _pumpCard(tester, _FakeWeatherRepository());

    expect(tester.takeException(), isNull);
  });

  // 예전엔 한 번 조회한 뒤 다시 조회하는 경로가 없어서, 아침에 열어 둔 탭은 종일 그때의 기온과
  // 시간별 예보("지금" 표시)를 보여줬다.
  group('auto refresh', () {
    testWidgets('shows when the data was fetched', (tester) async {
      await _pumpCard(tester, _FakeWeatherRepository());

      expect(find.text('09:01 기준'), findsOneWidget);
    });

    testWidgets('refetches every 30 minutes and keeps the old data on screen meanwhile', (
      tester,
    ) async {
      // 조회에 2분이 걸리게 해서, 타이머가 돈 뒤 "받는 중"인 구간을 안정적으로 관찰한다.
      // 첫 조회가 끝나는 데 2분이 걸리므로 30분 타이머는 그로부터 약 28분 뒤에 돈다.
      final repository = _FakeWeatherRepository(delay: const Duration(minutes: 2));
      await _pumpCard(tester, repository);
      expect(repository.fetchCount, 1);

      await tester.pump(const Duration(minutes: 27));
      expect(repository.fetchCount, 1);

      await tester.pump(const Duration(seconds: 90));
      expect(repository.fetchCount, 2);
      // 다시 받는 동안에도 스피너로 바뀌지 않고 이전 값이 그대로 보인다.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('09:01 기준'), findsOneWidget);

      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expect(find.text('09:02 기준'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refetches when the app comes back after the data got old', (tester) async {
      final repository = _FakeWeatherRepository(age: const Duration(hours: 1));
      await _pumpCard(tester, repository);
      expect(repository.fetchCount, 1);

      await _backgroundThenResume(tester);
      await tester.pumpAndSettle();

      expect(repository.fetchCount, 2);
    });

    testWidgets('does not refetch on coming back within the 30 minute refresh interval', (
      tester,
    ) async {
      final repository = _FakeWeatherRepository(age: const Duration(minutes: 20));
      await _pumpCard(tester, repository);

      await _backgroundThenResume(tester);
      await tester.pumpAndSettle();

      expect(repository.fetchCount, 1);
    });

    testWidgets('keeps the last data and says so when a refresh fails, then recovers', (
      tester,
    ) async {
      final repository = _FakeWeatherRepository(delay: const Duration(seconds: 1));
      await _pumpCard(tester, repository);
      expect(find.text('09:01 기준'), findsOneWidget);

      repository.failing = true;
      await tester.pump(const Duration(minutes: 30));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // 멀쩡하던 날씨 화면이 에러 화면으로 바뀌지 않고, 마지막 값과 실패 사실을 함께 보여준다.
      expect(repository.fetchCount, 2);
      expect(find.text('다시 시도'), findsNothing);
      expect(find.text('갱신 실패 · 09:01 기준'), findsOneWidget);

      repository.failing = false;
      await tester.pump(const Duration(minutes: 30));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text('09:03 기준'), findsOneWidget);
      expect(find.textContaining('갱신 실패'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a first load that fails still shows the error screen', (tester) async {
      final repository = _FakeWeatherRepository()..failing = true;
      await _pumpCard(tester, repository);

      expect(find.text('다시 시도'), findsOneWidget);
    });
  });
}
