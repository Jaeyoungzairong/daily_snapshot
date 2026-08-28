import 'city_candidate.dart';
import 'weather_model.dart';

/// 날씨 데이터 소스 인터페이스.
/// 구현체: KmaWeatherRepository(사용중), OpenMeteoWeatherRepository(현재 미사용, 보존).
abstract class WeatherRepository {
  Future<List<CityCandidate>> searchCities(String query);

  Future<WeatherModel> fetchWeather(CityCandidate city);
}
