import '../../../core/network/api_client.dart';
import 'city_candidate.dart';
import 'city_geocoding_service.dart';
import 'weather_model.dart';
import 'weather_repository.dart';

/// Open-Meteo 기반 날씨 조회. 기상청(KmaWeatherRepository)으로 교체되어 현재는 쓰이지
/// 않지만, 기상청 API 키 발급이 막히는 등 나중에 다시 필요해질 수 있어 남겨둔다.
/// 전세계 어디든 조회 가능하다는 게 기상청 대비 장점이다.
class OpenMeteoWeatherRepository implements WeatherRepository {
  OpenMeteoWeatherRepository({ApiClient? apiClient, CityGeocodingService? geocodingService})
      : _apiClient = apiClient ?? ApiClient(),
        _geocodingService = geocodingService ?? CityGeocodingService(apiClient: apiClient);

  final ApiClient _apiClient;
  final CityGeocodingService _geocodingService;

  static final Uri _forecastBase = Uri.parse('https://api.open-meteo.com/v1/forecast');

  @override
  Future<List<CityCandidate>> searchCities(String query) {
    return _geocodingService.searchCities(query);
  }

  @override
  Future<WeatherModel> fetchWeather(CityCandidate city) async {
    final forecastUri = _forecastBase.replace(queryParameters: {
      'latitude': city.latitude.toString(),
      'longitude': city.longitude.toString(),
      'current': 'temperature_2m,weather_code,wind_speed_10m,precipitation',
      'hourly': 'temperature_2m,weather_code,precipitation_probability,precipitation',
      'daily': 'temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max',
      'forecast_days': '7',
      'timezone': 'auto',
    });
    final forecastJson = await _apiClient.getJson(forecastUri);

    return WeatherModel.fromJson(cityName: city.displayLabel, json: forecastJson);
  }

  @override
  Future<CityCandidate?> nearestCity(double latitude, double longitude) {
    // 현재 미사용 리포지토리라 좌표 기반 지역 조회는 구현하지 않음.
    throw UnimplementedError('OpenMeteoWeatherRepository는 좌표 기반 지역 조회를 지원하지 않습니다.');
  }
}
