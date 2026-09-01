import 'package:daily_snapshot/features/weather/data/kma_weather_repository.dart';
import 'package:daily_snapshot/features/weather/data/weather_model.dart';
import 'package:flutter_test/flutter_test.dart';

KmaItem _item(String date, String time, String category, String value) {
  return KmaItem(category: category, fcstDate: date, fcstTime: time, value: value);
}

void main() {
  group('buildWeatherModel · hourly window', () {
    test('keeps only the 24-hour window starting at the current hour, across midnight', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 23, 30),
        currentByCategory: {'T1H': '20.0', 'WSD': '1.0', 'PTY': '0'},
        forecastItems: [
          _item('20260828', '2200', 'TMP', '20'), // 현재 이전 → 제외
          _item('20260828', '2200', 'SKY', '1'),
          _item('20260828', '2200', 'PTY', '0'),
          _item('20260828', '2300', 'TMP', '19'), // 현재 시각(23시) → 포함, isNow
          _item('20260828', '2300', 'SKY', '1'),
          _item('20260828', '2300', 'PTY', '0'),
          _item('20260829', '0000', 'TMP', '18'), // 자정 넘어감 → 포함
          _item('20260829', '0000', 'SKY', '1'),
          _item('20260829', '0000', 'PTY', '0'),
          _item('20260829', '2200', 'TMP', '15'), // 24시간 경계 직전 → 포함
          _item('20260829', '2200', 'SKY', '3'),
          _item('20260829', '2200', 'PTY', '0'),
          _item('20260829', '2300', 'TMP', '14'), // 정확히 24시간 후 → 제외
          _item('20260829', '2300', 'SKY', '1'),
          _item('20260829', '2300', 'PTY', '0'),
        ],
      );

      expect(model.hourlyForecast, hasLength(3));
      expect(model.hourlyForecast[0].time, DateTime(2026, 8, 28, 23));
      expect(model.hourlyForecast[0].isNow, isTrue);
      expect(model.hourlyForecast[1].time, DateTime(2026, 8, 29, 0));
      expect(model.hourlyForecast[1].isNow, isFalse);
      expect(model.hourlyForecast[2].time, DateTime(2026, 8, 29, 22));
      expect(model.hourlyForecast[2].condition, WeatherCondition.partlyCloudy);
      // POP/PCP 항목이 없는 슬롯은 강수확률 0, 강수량 null이어야 함.
      expect(model.hourlyForecast[0].precipitationProbability, 0);
      expect(model.hourlyForecast[0].precipitationAmount, isNull);
    });

    test('parses POP/PCP into precipitation fields, treating "강수없음" as null', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '20.0', 'WSD': '1.0', 'PTY': '0'},
        forecastItems: [
          _item('20260828', '1000', 'TMP', '20'),
          _item('20260828', '1000', 'SKY', '1'),
          _item('20260828', '1000', 'PTY', '0'),
          _item('20260828', '1000', 'POP', '70'),
          _item('20260828', '1000', 'PCP', '1.0mm'),
          _item('20260828', '1100', 'TMP', '21'),
          _item('20260828', '1100', 'SKY', '1'),
          _item('20260828', '1100', 'PTY', '0'),
          _item('20260828', '1100', 'POP', '0'),
          _item('20260828', '1100', 'PCP', '강수없음'),
        ],
      );

      expect(model.hourlyForecast[0].precipitationProbability, 70);
      expect(model.hourlyForecast[0].precipitationAmount, '1mm');
      expect(model.hourlyForecast[1].precipitationProbability, 0);
      expect(model.hourlyForecast[1].precipitationAmount, isNull);
    });

    test('simplifies "미만"/"이상" PCP text into inequality symbols', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '20.0', 'WSD': '1.0', 'PTY': '0'},
        forecastItems: [
          _item('20260828', '1000', 'TMP', '20'),
          _item('20260828', '1000', 'SKY', '1'),
          _item('20260828', '1000', 'PTY', '0'),
          _item('20260828', '1000', 'PCP', '1mm 미만'),
          _item('20260828', '1100', 'TMP', '21'),
          _item('20260828', '1100', 'SKY', '1'),
          _item('20260828', '1100', 'PTY', '0'),
          _item('20260828', '1100', 'PCP', '50.0mm 이상'),
          _item('20260828', '1200', 'TMP', '21'),
          _item('20260828', '1200', 'SKY', '1'),
          _item('20260828', '1200', 'PTY', '0'),
          _item('20260828', '1200', 'PCP', '30.0~50.0mm'),
        ],
      );

      expect(model.hourlyForecast[0].precipitationAmount, '<1mm');
      expect(model.hourlyForecast[1].precipitationAmount, '>50mm');
      expect(model.hourlyForecast[2].precipitationAmount, '30~50mm');
    });
  });

  group('buildWeatherModel · daily forecast', () {
    test('caps at 3 days and falls back to hourly TMP when TMN/TMX are missing', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '27.0', 'WSD': '1.0', 'PTY': '0'},
        forecastItems: [
          // 오늘(28일): 06시가 이미 지나 TMN이 없음 → TMP 최솟값(25)으로 대체돼야 함.
          _item('20260828', '0900', 'TMP', '25'),
          _item('20260828', '0900', 'SKY', '1'),
          _item('20260828', '0900', 'PTY', '0'),
          _item('20260828', '1000', 'TMP', '27'),
          _item('20260828', '1000', 'SKY', '1'),
          _item('20260828', '1000', 'PTY', '0'),
          _item('20260828', '1500', 'TMX', '31'),
          _item('20260828', '1500', 'SKY', '1'),
          _item('20260828', '1500', 'PTY', '0'),
          // 내일(29일): TMN/TMX가 모두 있으므로 그 값을 그대로 써야 함(TMP 범위와 다름).
          _item('20260829', '0000', 'TMP', '22'),
          _item('20260829', '0000', 'SKY', '1'),
          _item('20260829', '0000', 'PTY', '0'),
          _item('20260829', '0600', 'TMN', '24.0'),
          _item('20260829', '0600', 'SKY', '1'),
          _item('20260829', '0600', 'PTY', '0'),
          _item('20260829', '1200', 'TMP', '27'),
          _item('20260829', '1200', 'SKY', '1'),
          _item('20260829', '1200', 'PTY', '0'),
          _item('20260829', '1500', 'TMX', '29.0'),
          _item('20260829', '1500', 'SKY', '1'),
          _item('20260829', '1500', 'PTY', '0'),
          // 모레(30일): 최소 데이터.
          _item('20260830', '1200', 'TMP', '26'),
          _item('20260830', '0600', 'TMN', '23.0'),
          _item('20260830', '1500', 'TMX', '29.0'),
          _item('20260830', '1200', 'SKY', '1'),
          _item('20260830', '1200', 'PTY', '0'),
          // 글피(31일): 3일 캡에 걸려 제외돼야 함.
          _item('20260831', '1200', 'TMP', '20'),
          _item('20260831', '1200', 'SKY', '1'),
          _item('20260831', '1200', 'PTY', '0'),
        ],
      );

      expect(model.dailyForecast, hasLength(3));
      expect(model.dailyForecast.map((d) => d.date), [
        DateTime(2026, 8, 28),
        DateTime(2026, 8, 29),
        DateTime(2026, 8, 30),
      ]);
      expect(model.dailyForecast[0].minTemp, 25); // TMN 없음 → TMP 최솟값
      expect(model.dailyForecast[0].maxTemp, 31);
      expect(model.dailyForecast[1].minTemp, 24.0); // TMN 있음 → 그대로
      expect(model.dailyForecast[1].maxTemp, 29.0);
    });

    test('daily precipitation probability is the max POP across the day\'s slots', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 6),
        currentByCategory: {'T1H': '20.0', 'WSD': '1.0', 'PTY': '0'},
        forecastItems: [
          _item('20260828', '0900', 'TMP', '20'),
          _item('20260828', '0900', 'SKY', '1'),
          _item('20260828', '0900', 'PTY', '0'),
          _item('20260828', '0900', 'POP', '30'),
          _item('20260828', '1200', 'TMP', '25'),
          _item('20260828', '1200', 'SKY', '1'),
          _item('20260828', '1200', 'PTY', '0'),
          _item('20260828', '1200', 'POP', '80'),
          _item('20260828', '1500', 'TMP', '24'),
          _item('20260828', '1500', 'SKY', '1'),
          _item('20260828', '1500', 'PTY', '0'),
          _item('20260828', '1500', 'POP', '50'),
        ],
      );

      expect(model.dailyForecast[0].precipitationProbability, 80);
    });
  });

  group('buildWeatherModel · current condition', () {
    test('combines UltraSrtNcst precipitation with the same-hour VilageFcst sky state', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '29.3', 'WSD': '2.9', 'PTY': '0'},
        forecastItems: [
          _item('20260828', '1000', 'TMP', '27'),
          _item('20260828', '1000', 'SKY', '4'), // 흐림
          _item('20260828', '1000', 'PTY', '0'),
        ],
      );

      expect(model.currentTemp, 29.3);
      expect(model.windSpeed, 2.9);
      expect(model.condition, WeatherCondition.cloudy);
    });

    test('precipitation from UltraSrtNcst takes priority over VilageFcst sky state', () {
      final model = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '18.0', 'WSD': '3.0', 'PTY': '1'}, // 실황: 비
        forecastItems: [
          _item('20260828', '1000', 'TMP', '18'),
          _item('20260828', '1000', 'SKY', '1'), // 예보상 맑음이지만 실황이 우선
          _item('20260828', '1000', 'PTY', '0'),
        ],
      );

      expect(model.condition, WeatherCondition.rain);
    });

    test('current precipitation comes from RN1, a unitless number where "0" means no rain', () {
      // RN1은 PCP와 달리 "강수없음" 문자열이 아니라 단위 없는 순수 숫자로 온다.
      final withRain = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '18.0', 'WSD': '3.0', 'PTY': '1', 'RN1': '1.0'},
        forecastItems: [
          _item('20260828', '1000', 'TMP', '18'),
          _item('20260828', '1000', 'SKY', '1'),
          _item('20260828', '1000', 'PTY', '0'),
        ],
      );
      expect(withRain.precipitationAmount, '1mm');

      final noRain = buildWeatherModel(
        cityName: '테스트시',
        now: DateTime(2026, 8, 28, 10, 1),
        currentByCategory: {'T1H': '18.0', 'WSD': '3.0', 'PTY': '0', 'RN1': '0'},
        forecastItems: [
          _item('20260828', '1000', 'TMP', '18'),
          _item('20260828', '1000', 'SKY', '1'),
          _item('20260828', '1000', 'PTY', '0'),
        ],
      );
      expect(noRain.precipitationAmount, isNull);
    });
  });
}
