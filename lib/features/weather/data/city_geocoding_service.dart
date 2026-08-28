import '../../../core/network/api_client.dart';
import 'city_candidate.dart';

/// 도시 이름으로 후보 지역을 찾는 지오코딩(전세계). 현재 활성 경로인 기상청은
/// KmaRegionDirectory(기상청 공식 지점 목록)로 한국 지역만 검색하므로 이 서비스를 쓰지
/// 않는다. 전세계 어디든 검색 가능해야 하는 OpenMeteoWeatherRepository(현재 미사용,
/// 보존) 전용으로 남겨둔다.
class CityGeocodingService {
  CityGeocodingService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  static final Uri _geocodingBase = Uri.parse('https://geocoding-api.open-meteo.com/v1/search');

  /// 도시 이름으로 후보 목록을 검색한다. 동명 지명(같은 이름의 여러 나라/지역 도시)이
  /// 흔하기 때문에 자동으로 하나를 고르지 않고, 후보를 모두 반환해 사용자가 직접 선택하게 한다.
  Future<List<CityCandidate>> searchCities(String query) async {
    final uri = _geocodingBase.replace(queryParameters: {
      'name': query,
      'count': '50',
      'language': 'ko',
      'format': 'json',
    });
    final json = await _apiClient.getJson(uri);
    final results = json['results'] as List?;
    if (results == null || results.isEmpty) return [];

    final candidates = results.map((e) => CityCandidate.fromJson(e as Map<String, dynamic>)).toList();

    // 인구 데이터가 있는 후보(실제 잘 알려진 도시일 가능성이 높음)를 인구 많은 순으로
    // 먼저 보여주고, 인구 데이터가 없는 무명 지명은 원래 순서 그대로 뒤에 붙인다.
    final withPopulation = candidates.where((c) => c.population != null).toList()
      ..sort((a, b) => b.population!.compareTo(a.population!));
    final withoutPopulation = candidates.where((c) => c.population == null).toList();

    return [...withPopulation, ...withoutPopulation];
  }
}
