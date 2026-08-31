import 'city_candidate.dart';
import 'weather_model.dart';

/// 날씨 데이터 소스 인터페이스.
/// 구현체: KmaWeatherRepository(사용중), OpenMeteoWeatherRepository(현재 미사용, 보존).
abstract class WeatherRepository {
  Future<List<CityCandidate>> searchCities(String query);

  Future<WeatherModel> fetchWeather(CityCandidate city);

  /// 좌표에서 가장 가까운 지역을 찾는다("내 위치로 찾기" 기능용). 지원 범위 밖 좌표면 null.
  Future<CityCandidate?> nearestCity(double latitude, double longitude);
}
