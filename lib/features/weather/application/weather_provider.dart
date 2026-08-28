import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/city_candidate.dart';
import '../data/kma_weather_repository.dart';
import '../data/weather_model.dart';
import '../data/weather_repository.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return KmaWeatherRepository();
});

/// 검색어로 도시 후보 목록을 조회한다. 빈 문자열이면 빈 목록을 반환한다.
/// 자동완성으로 타이핑마다 새 쿼리가 생성되므로, 더 이상 보이지 않는 검색어의 캐시가
/// 계속 쌓이지 않도록 autoDispose를 쓴다.
final citySearchProvider = FutureProvider.autoDispose.family<List<CityCandidate>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return [];
  final repository = ref.watch(weatherRepositoryProvider);
  return repository.searchCities(trimmed);
});

class SelectedCityNotifier extends Notifier<CityCandidate> {
  @override
  CityCandidate build() => const CityCandidate(
        name: '안양시동안구',
        latitude: 37.3897,
        longitude: 126.953356,
        admin1: '경기도',
        country: '대한민국',
      );

  void select(CityCandidate city) => state = city;
}

final selectedCityProvider = NotifierProvider<SelectedCityNotifier, CityCandidate>(
  SelectedCityNotifier.new,
);

final weatherProvider = FutureProvider.family<WeatherModel, CityCandidate>((ref, city) async {
  final repository = ref.watch(weatherRepositoryProvider);
  return repository.fetchWeather(city);
});
