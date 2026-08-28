import 'package:daily_snapshot/features/weather/data/weather_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeatherModel.fromJson', () {
    test('parses Open-Meteo forecast response correctly', () {
      final json = {
        'current': {
          'time': '2026-08-27T14:00',
          'temperature_2m': 23.4,
          'weather_code': 1,
          'wind_speed_10m': 12.3,
          'precipitation': 0.0,
        },
        'hourly': {
          'time': ['2026-08-27T14:00', '2026-08-27T15:00'],
          'temperature_2m': [23.4, 22.9],
          'weather_code': [1, 1],
          'precipitation_probability': [10, 20],
          'precipitation': [0.0, 0.5],
        },
        'daily': {
          'time': ['2026-08-27', '2026-08-28', '2026-08-29'],
          'temperature_2m_max': [27.1, 26.0, 25.5],
          'temperature_2m_min': [18.9, 19.2, 18.0],
          'weather_code': [1, 61, 3],
          'precipitation_probability_max': [10, 60, 20],
        },
      };

      final model = WeatherModel.fromJson(cityName: 'Seoul', json: json);

      expect(model.cityName, 'Seoul');
      expect(model.currentTemp, 23.4);
      expect(model.condition, WeatherCondition.partlyCloudy);
      expect(model.windSpeed, 12.3);
      expect(model.maxTemp, 27.1);
      expect(model.minTemp, 18.9);
      expect(model.precipitationAmount, isNull); // 현재 강수량 0 → null
      expect(model.hourlyForecast[1].precipitationProbability, 20);
      expect(model.hourlyForecast[1].precipitationAmount, '0.5mm');
      expect(model.dailyForecast[1].precipitationProbability, 60);
    });

    test('description and icon are derived from weather code', () {
      final model = WeatherModel.fromJson(cityName: 'Tokyo', json: {
        'current': {
          'time': '2026-08-27T14:00',
          'temperature_2m': 10.0,
          'weather_code': 95,
          'wind_speed_10m': 5.0,
          'precipitation': 2.0,
        },
        'hourly': {
          'time': ['2026-08-27T14:00'],
          'temperature_2m': [10.0],
          'weather_code': [95],
          'precipitation_probability': [80],
          'precipitation': [2.0],
        },
        'daily': {
          'time': ['2026-08-27'],
          'temperature_2m_max': [12.0],
          'temperature_2m_min': [8.0],
          'weather_code': [95],
          'precipitation_probability_max': [80],
        },
      });

      expect(model.description, '뇌우');
    });

    test('parses the full daily forecast array, not just the first day', () {
      final model = WeatherModel.fromJson(cityName: 'Seoul', json: {
        'current': {
          'time': '2026-08-27T14:00',
          'temperature_2m': 23.4,
          'weather_code': 1,
          'wind_speed_10m': 12.3,
          'precipitation': 0.0,
        },
        'hourly': {
          'time': ['2026-08-27T14:00'],
          'temperature_2m': [23.4],
          'weather_code': [1],
          'precipitation_probability': [10],
          'precipitation': [0.0],
        },
        'daily': {
          'time': [
            '2026-08-27',
            '2026-08-28',
            '2026-08-29',
            '2026-08-30',
            '2026-08-31',
            '2026-09-01',
            '2026-09-02',
          ],
          'temperature_2m_max': [30.0, 28.8, 28.7, 26.8, 28.2, 26.1, 26.5],
          'temperature_2m_min': [22.2, 23.9, 24.6, 22.5, 22.3, 21.5, 21.5],
          'weather_code': [2, 61, 55, 55, 3, 51, 81],
          'precipitation_probability_max': [10, 60, 40, 40, 5, 30, 70],
        },
      });

      expect(model.dailyForecast, hasLength(7));
      expect(model.dailyForecast.first.date, DateTime(2026, 8, 27));
      expect(model.dailyForecast.first.maxTemp, 30.0);
      expect(model.dailyForecast.last.date, DateTime(2026, 9, 2));
      expect(model.dailyForecast.last.condition, WeatherCondition.showers);
      expect(model.dailyForecast[1].description, '비');
    });

    test('hourlyForecast keeps only today, from the current hour onward', () {
      final model = WeatherModel.fromJson(cityName: 'Seoul', json: {
        'current': {
          'time': '2026-08-27T14:00',
          'temperature_2m': 23.4,
          'weather_code': 1,
          'wind_speed_10m': 12.3,
          'precipitation': 0.0,
        },
        'hourly': {
          'time': [
            '2026-08-27T00:00', // 현재 이전 시각 → 제외
            '2026-08-27T13:00', // 현재 이전 시각 → 제외
            '2026-08-27T14:00', // 현재 시각 → 포함, isNow
            '2026-08-27T15:00',
            '2026-08-27T23:00',
            '2026-08-28T00:00', // 다음 날 → 제외
          ],
          'temperature_2m': [17.0, 21.0, 23.4, 22.9, 19.0, 18.5],
          'weather_code': [1, 1, 1, 61, 3, 3],
          'precipitation_probability': [10, 10, 20, 30, 40, 40],
          'precipitation': [0.0, 0.0, 0.0, 0.5, 1.0, 1.0],
        },
        'daily': {
          'time': ['2026-08-27', '2026-08-28'],
          'temperature_2m_max': [27.1, 26.0],
          'temperature_2m_min': [18.9, 19.2],
          'weather_code': [1, 61],
          'precipitation_probability_max': [40, 60],
        },
      });

      expect(model.hourlyForecast, hasLength(3));
      expect(model.hourlyForecast.first.time, DateTime(2026, 8, 27, 14));
      expect(model.hourlyForecast.first.isNow, isTrue);
      expect(model.hourlyForecast.first.temperature, 23.4);
      expect(model.hourlyForecast.last.time, DateTime(2026, 8, 27, 23));
      expect(model.hourlyForecast.last.isNow, isFalse);
      expect(model.hourlyForecast.last.precipitationProbability, 40);
      expect(model.hourlyForecast.last.precipitationAmount, '1.0mm');
    });
  });

  group('WeatherCondition.fromKmaSkyPty', () {
    test('uses sky state when there is no precipitation', () {
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 0), WeatherCondition.clear);
      expect(WeatherCondition.fromKmaSkyPty(sky: 3, pty: 0), WeatherCondition.partlyCloudy);
      expect(WeatherCondition.fromKmaSkyPty(sky: 4, pty: 0), WeatherCondition.cloudy);
    });

    test('precipitation type overrides sky state', () {
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 1), WeatherCondition.rain);
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 2), WeatherCondition.sleet);
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 3), WeatherCondition.snow);
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 4), WeatherCondition.showers);
    });

    test('초단기예보 전용 세분류(5/6/7)도 대응하는 단기예보 코드와 같은 조건으로 매핑된다', () {
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 5), WeatherCondition.rain);
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 6), WeatherCondition.sleet);
      expect(WeatherCondition.fromKmaSkyPty(sky: 1, pty: 7), WeatherCondition.snow);
    });
  });
}
