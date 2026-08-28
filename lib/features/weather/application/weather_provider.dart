import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/city_candidate.dart';
import '../data/kma_weather_repository.dart';
import '../data/weather_model.dart';
import '../data/weather_repository.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return KmaWeatherRepository();
});

/// 검색어로 도시 후보 목록을 조회한다. 빈 문자열이면 빈 목록을 반환한다.
final citySearchProvider = FutureProvider.family<List<CityCandidate>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return [];
  final repository = ref.watch(weatherRepositoryProvider);
  return repository.searchCities(trimmed);
});

class SelectedCityNotifier extends Notifier<CityCandidate> {
  @override
  CityCandidate build() => const CityCandidate(
        name: '안양시',
        latitude: 37.3925,
        longitude: 126.92694,
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
