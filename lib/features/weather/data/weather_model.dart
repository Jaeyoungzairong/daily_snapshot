import 'package:flutter/material.dart';

class WeatherModel {
  const WeatherModel({
    required this.cityName,
    required this.currentTemp,
    required this.weatherCode,
    required this.windSpeed,
    required this.maxTemp,
    required this.minTemp,
    required this.dailyForecast,
    required this.hourlyForecast,
  });

  factory WeatherModel.fromJson({
    required String cityName,
    required Map<String, dynamic> json,
  }) {
    final current = json['current'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;
    final hourly = json['hourly'] as Map<String, dynamic>;

    final dates = (daily['time'] as List).cast<String>();
    final maxTemps = (daily['temperature_2m_max'] as List).cast<num>();
    final minTemps = (daily['temperature_2m_min'] as List).cast<num>();
    final weatherCodes = (daily['weather_code'] as List).cast<num>();

    final dailyForecast = List.generate(dates.length, (i) {
      return DailyForecast(
        date: DateTime.parse(dates[i]),
        maxTemp: maxTemps[i].toDouble(),
        minTemp: minTemps[i].toDouble(),
        weatherCode: weatherCodes[i].toInt(),
      );
    });

    final currentTime = DateTime.parse(current['time'] as String);
    final hourTimes = (hourly['time'] as List).cast<String>();
    final hourTemps = (hourly['temperature_2m'] as List).cast<num>();
    final hourCodes = (hourly['weather_code'] as List).cast<num>();

    final hourlyForecast = <HourlyForecast>[];
    for (var i = 0; i < hourTimes.length; i++) {
      final time = DateTime.parse(hourTimes[i]);
      final isToday = time.year == currentTime.year &&
          time.month == currentTime.month &&
          time.day == currentTime.day;
      final isPast = time.isBefore(DateTime(currentTime.year, currentTime.month, currentTime.day, currentTime.hour));
      if (isToday && !isPast) {
        hourlyForecast.add(HourlyForecast(
          time: time,
          temperature: hourTemps[i].toDouble(),
          weatherCode: hourCodes[i].toInt(),
          isNow: time.hour == currentTime.hour,
        ));
      }
    }

    return WeatherModel(
      cityName: cityName,
      currentTemp: (current['temperature_2m'] as num).toDouble(),
      weatherCode: (current['weather_code'] as num).toInt(),
      windSpeed: (current['wind_speed_10m'] as num).toDouble(),
      maxTemp: dailyForecast.first.maxTemp,
      minTemp: dailyForecast.first.minTemp,
      dailyForecast: dailyForecast,
      hourlyForecast: hourlyForecast,
    );
  }

  final String cityName;
  final double currentTemp;
  final int weatherCode;
  final double windSpeed;
  final num maxTemp;
  final num minTemp;

  /// 오늘을 포함해 Open-Meteo가 기본으로 제공하는 최대 7일치 일별 예보.
  final List<DailyForecast> dailyForecast;

  /// 오늘 현재 시각 이후부터 자정까지의 시간별 예보.
  final List<HourlyForecast> hourlyForecast;

  String get description => weatherDescription(weatherCode);
  IconData get icon => weatherIcon(weatherCode);
}

class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
  });

  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;

  String get description => weatherDescription(weatherCode);
  IconData get icon => weatherIcon(weatherCode);
}

class HourlyForecast {
  const HourlyForecast({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.isNow,
  });

  final DateTime time;
  final double temperature;
  final int weatherCode;

  /// 오늘 시간별 예보 중 현재 시각(API가 응답한 `current.time` 기준)과 같은 시간대인지 여부.
  final bool isNow;

  String get description => weatherDescription(weatherCode);
  IconData get icon => weatherIcon(weatherCode);
}

/// WMO Weather interpretation codes (Open-Meteo)
String weatherDescription(int code) {
  switch (code) {
    case 0:
      return '맑음';
    case 1:
    case 2:
      return '대체로 맑음';
    case 3:
      return '흐림';
    case 45:
    case 48:
      return '안개';
    case 51:
    case 53:
    case 55:
      return '이슬비';
    case 56:
    case 57:
      return '어는 이슬비';
    case 61:
    case 63:
    case 65:
      return '비';
    case 66:
    case 67:
      return '어는 비';
    case 71:
    case 73:
    case 75:
      return '눈';
    case 77:
      return '싸락눈';
    case 80:
    case 81:
    case 82:
      return '소나기';
    case 85:
    case 86:
      return '눈 소나기';
    case 95:
      return '뇌우';
    case 96:
    case 99:
      return '우박 동반 뇌우';
    default:
      return '알 수 없음';
  }
}

IconData weatherIcon(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code == 1 || code == 2) return Icons.wb_cloudy;
  if (code == 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 51 && code <= 57) return Icons.water_drop_outlined; // 이슬비/어는 이슬비
  if (code >= 61 && code <= 67) return Icons.water_drop; // 비/어는 비
  if (code >= 71 && code <= 77) return Icons.ac_unit;
  if (code >= 80 && code <= 82) return Icons.umbrella; // 소나기
  if (code >= 85 && code <= 86) return Icons.ac_unit;
  if (code >= 95) return Icons.thunderstorm;
  return Icons.help_outline;
}
