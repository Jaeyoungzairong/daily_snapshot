import '../../../core/config/local_config.dart';
import '../../../core/network/api_client.dart';
import 'city_candidate.dart';
import 'kma_base_time.dart';
import 'kma_grid.dart';
import 'kma_region_directory.dart';
import 'weather_model.dart';
import 'weather_repository.dart';

/// 기상청 단기예보 조회서비스(VilageFcstInfoService_2.0) 기반 날씨 조회.
/// 초단기실황(getUltraSrtNcst)으로 "현재" 기온/풍속을, 단기예보(getVilageFcst)로
/// 시간별/일별 예보를 받아온다. 도시 검색은 기상청이 배포하는 지점 목록(KmaRegionDirectory)을
/// 그대로 쓴다 — 한국 좌표만 지원하기도 하고, 한국 행정구역 검색 정확도도 더 높다.
class KmaWeatherRepository implements WeatherRepository {
  KmaWeatherRepository({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  static const String _baseUrl = 'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0';

  @override
  Future<List<CityCandidate>> searchCities(String query) async {
    final directory = await KmaRegionDirectory.load();
    return directory.search(query);
  }

  @override
  Future<CityCandidate?> nearestCity(double latitude, double longitude) async {
    final directory = await KmaRegionDirectory.load();
    return directory.nearest(latitude, longitude);
  }

  @override
  Future<WeatherModel> fetchWeather(CityCandidate city) async {
    final grid = KmaGrid.fromLatLon(latitude: city.latitude, longitude: city.longitude);
    final now = DateTime.now();

    final currentItems = await _fetchItems(
      operation: 'getUltraSrtNcst',
      baseDateTime: KmaBaseTime.ultraSrtNcst(now),
      grid: grid,
      numOfRows: 20,
      valueKey: 'obsrValue',
    );
    final forecastItems = await _fetchItems(
      operation: 'getVilageFcst',
      baseDateTime: KmaBaseTime.vilageFcst(now),
      grid: grid,
      numOfRows: 1000,
      valueKey: 'fcstValue',
    );

    return buildWeatherModel(
      cityName: city.displayLabel,
      now: now,
      currentByCategory: {for (final item in currentItems) item.category: item.value},
      forecastItems: forecastItems,
    );
  }

  Future<List<KmaItem>> _fetchItems({
    required String operation,
    required ({String baseDate, String baseTime}) baseDateTime,
    required KmaGrid grid,
    required int numOfRows,
    required String valueKey,
  }) async {
    final uri = Uri.parse('$_baseUrl/$operation').replace(queryParameters: {
      'serviceKey': LocalConfig.kmaServiceKey,
      'pageNo': '1',
      'numOfRows': '$numOfRows',
      'dataType': 'JSON',
      'base_date': baseDateTime.baseDate,
      'base_time': baseDateTime.baseTime,
      'nx': '${grid.nx}',
      'ny': '${grid.ny}',
    });
    final json = await _apiClient.getJson(uri);

    final header = (json['response'] as Map<String, dynamic>)['header'] as Map<String, dynamic>;
    if (header['resultCode'] != '00') {
      throw ApiException('기상청 API 오류: ${header['resultMsg']}');
    }

    final body = (json['response'] as Map<String, dynamic>)['body'] as Map<String, dynamic>;
    // 결과가 없을 때 items가 빈 문자열로 오는 경우가 있어(공공데이터포털 흔한 케이스) 방어한다.
    final itemsField = body['items'];
    final rawItems = itemsField is Map<String, dynamic> ? (itemsField['item'] as List? ?? const []) : const [];

    return rawItems.map((e) {
      final map = e as Map<String, dynamic>;
      return KmaItem(
        category: map['category'] as String,
        fcstDate: (map['fcstDate'] ?? map['baseDate']) as String,
        fcstTime: (map['fcstTime'] ?? map['baseTime']) as String,
        value: map[valueKey] as String,
      );
    }).toList();
  }
}

/// 기상청 API 응답의 관측/예보 한 항목. getUltraSrtNcst는 fcstDate/fcstTime이 없어
/// baseDate/baseTime으로 대체된다(즉 "그 시각의 관측값"이라는 의미로 동일하게 취급).
class KmaItem {
  const KmaItem({
    required this.category,
    required this.fcstDate,
    required this.fcstTime,
    required this.value,
  });

  final String category;
  final String fcstDate;
  final String fcstTime;
  final String value;
}

/// getUltraSrtNcst(현재)와 getVilageFcst(시간별/일별) 항목들을 [WeatherModel]로 조립한다.
/// 리포지토리 본체와 분리해 순수 함수로 테스트하기 쉽게 한다.
WeatherModel buildWeatherModel({
  required String cityName,
  required DateTime now,
  required Map<String, String> currentByCategory,
  required List<KmaItem> forecastItems,
}) {
  // "yyyyMMddHHmm" 슬롯 키 → 카테고리 → 값.
  final slots = <String, Map<String, String>>{};
  for (final item in forecastItems) {
    final key = '${item.fcstDate}${item.fcstTime}';
    (slots[key] ??= {})[item.category] = item.value;
  }

  DateTime slotTime(String key) => DateTime(
        int.parse(key.substring(0, 4)),
        int.parse(key.substring(4, 6)),
        int.parse(key.substring(6, 8)),
        int.parse(key.substring(8, 10)),
      );

  final sortedKeys = slots.keys.toList()..sort();
  final nowHour = DateTime(now.year, now.month, now.day, now.hour);
  final nowKey = _keyFor(nowHour);

  // 시간별 예보: 현재 시각부터 24시간 후까지.
  final windowEnd = nowHour.add(const Duration(hours: 24));
  final hourlyForecast = <HourlyForecast>[];
  for (final key in sortedKeys) {
    final time = slotTime(key);
    if (time.isBefore(nowHour) || !time.isBefore(windowEnd)) continue;
    final category = slots[key]!;
    final tmp = category['TMP'];
    if (tmp == null) continue;
    hourlyForecast.add(HourlyForecast(
      time: time,
      temperature: double.parse(tmp),
      condition: WeatherCondition.fromKmaSkyPty(
        sky: int.tryParse(category['SKY'] ?? '') ?? 1,
        pty: int.tryParse(category['PTY'] ?? '') ?? 0,
      ),
      isNow: time == nowHour,
      precipitationProbability: int.tryParse(category['POP'] ?? '') ?? 0,
      precipitationAmount: _noPrecipitation(category['PCP']),
    ));
  }

  // 일별 예보: 오늘 포함 3일치. 단기예보 해상도가 3일째부터 3시간 간격으로 성기어지므로
  // 그 이전까지만 보여준다(4일 이상은 중기예보 API를 추가로 붙여야 함).
  final keysByDate = <String, List<String>>{};
  for (final key in sortedKeys) {
    keysByDate.putIfAbsent(key.substring(0, 8), () => []).add(key);
  }
  final dailyForecast = <DailyForecast>[];
  for (final dateStr in (keysByDate.keys.toList()..sort()).take(3)) {
    final keysOfDate = keysByDate[dateStr]!;
    final tmps = <double>[];
    double? tmx;
    double? tmn;
    String? repSky;
    String? repPty;
    int? repDistanceToNoon;
    var maxPop = 0;

    for (final key in keysOfDate) {
      final category = slots[key]!;
      final tmp = category['TMP'];
      if (tmp != null) tmps.add(double.parse(tmp));
      if (category['TMX'] != null) tmx = double.parse(category['TMX']!);
      if (category['TMN'] != null) tmn = double.parse(category['TMN']!);
      final pop = int.tryParse(category['POP'] ?? '') ?? 0;
      if (pop > maxPop) maxPop = pop;

      // 낮 12시에 가장 가까운 슬롯의 하늘상태를 그날의 대표 아이콘으로 쓴다.
      final hour = int.parse(key.substring(8, 10));
      final distance = (hour - 12).abs();
      if (repDistanceToNoon == null || distance < repDistanceToNoon) {
        repDistanceToNoon = distance;
        repSky = category['SKY'];
        repPty = category['PTY'];
      }
    }
    if (tmps.isEmpty) continue;

    dailyForecast.add(DailyForecast(
      date: DateTime(int.parse(dateStr.substring(0, 4)), int.parse(dateStr.substring(4, 6)), int.parse(dateStr.substring(6, 8))),
      // TMN/TMX(일 최저/최고)는 발표된 시각(각각 06시/15시)이 이미 지났으면 응답에 없다.
      // 그럴 땐 그 날짜에 남아있는 시간별 기온(TMP) 중 최댓값/최솟값으로 대체한다.
      maxTemp: tmx ?? tmps.reduce((a, b) => a > b ? a : b),
      minTemp: tmn ?? tmps.reduce((a, b) => a < b ? a : b),
      condition: WeatherCondition.fromKmaSkyPty(
        sky: int.tryParse(repSky ?? '') ?? 1,
        pty: int.tryParse(repPty ?? '') ?? 0,
      ),
      // 하루 중 슬롯별 강수확률(POP)의 최댓값을 그날의 대표값으로 쓴다.
      precipitationProbability: maxPop,
    ));
  }

  // 현재 날씨: 초단기실황(기온 T1H, 풍속 WSD, 강수형태 PTY)에 단기예보의 같은 시각
  // 하늘상태(SKY)를 더한다 — 초단기실황은 하늘상태를 안 주기 때문.
  final currentPty = int.tryParse(currentByCategory['PTY'] ?? '') ?? 0;
  final currentSky = int.tryParse(slots[nowKey]?['SKY'] ?? '') ?? 1;

  return WeatherModel(
    cityName: cityName,
    currentTemp: double.parse(currentByCategory['T1H']!),
    condition: WeatherCondition.fromKmaSkyPty(sky: currentSky, pty: currentPty),
    windSpeed: double.parse(currentByCategory['WSD']!),
    maxTemp: dailyForecast.first.maxTemp,
    minTemp: dailyForecast.first.minTemp,
    dailyForecast: dailyForecast,
    hourlyForecast: hourlyForecast,
    // 초단기실황의 실측 강수량(RN1). 단기예보(PCP)와 달리 "지금" 시점의 실제값이다.
    precipitationAmount: _currentPrecipitationText(currentByCategory['RN1']),
  );
}

String _keyFor(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}${dt.hour.toString().padLeft(2, '0')}00';

/// 단기예보 PCP는 강수가 없을 때 "강수없음" 텍스트를 값으로 준다. UI에서는 이를
/// 표시하지 않는 게 자연스러워 null로 정규화한다(그 외 값은 "1.0mm" 같은 원문 그대로 사용).
String? _noPrecipitation(String? value) {
  if (value == null || value == '강수없음') return null;
  return value;
}

/// 초단기실황 RN1은 PCP와 달리 "강수없음" 텍스트가 아니라 단위 없는 순수 숫자(mm)로
/// 온다("0"이면 강수 없음). 0이면 표시하지 않고, 그 외에는 단위를 붙여 보여준다.
String? _currentPrecipitationText(String? rn1) {
  final value = double.tryParse(rn1 ?? '');
  if (value == null || value == 0) return null;
  return '${rn1}mm';
}
