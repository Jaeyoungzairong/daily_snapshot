import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/key_value_store.dart';
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

const CityCandidate _defaultCity = CityCandidate(
  name: '서울특별시',
  latitude: 37.563569,
  longitude: 126.980008,
);

class SelectedCityNotifier extends Notifier<CityCandidate> {
  SelectedCityNotifier({this.initial = _defaultCity, KeyValueStore? store}) : _providedStore = store;

  static const String _key = 'weather_selected_city';

  final CityCandidate initial;
  final KeyValueStore? _providedStore;
  KeyValueStore? _store;

  // select()가 실제로 호출될 때만 저장소를 생성한다: 위젯 테스트 중 이 notifier를
  // 오버라이드하지 않고 렌더링만 하는 경우, 플러그인이 초기화되지 않은 상태에서
  // SharedPreferencesAsync() 생성만으로 예외가 나는 것을 막기 위함.
  KeyValueStore get _resolvedStore => _store ??= _providedStore ?? SharedPreferencesKeyValueStore();

  /// 마지막으로 선택한 도시를 앱 시작(runApp) 전에 미리 읽어온다. 저장된 값이 없거나
  /// 파싱에 실패하면 기본 도시를 쓴다.
  static Future<CityCandidate> loadInitial([KeyValueStore? store]) async {
    final resolvedStore = store ?? SharedPreferencesKeyValueStore();
    final raw = await resolvedStore.getString(_key);
    if (raw == null) return _defaultCity;
    try {
      return CityCandidate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return _defaultCity;
    }
  }

  @override
  CityCandidate build() => initial;

  void select(CityCandidate city) {
    state = city;
    _resolvedStore.setString(_key, jsonEncode(city.toJson()));
  }
}

final selectedCityProvider = NotifierProvider<SelectedCityNotifier, CityCandidate>(
  SelectedCityNotifier.new,
);

final weatherProvider = FutureProvider.family<WeatherModel, CityCandidate>((ref, city) async {
  final repository = ref.watch(weatherRepositoryProvider);
  return repository.fetchWeather(city);
});
