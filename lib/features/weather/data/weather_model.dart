import 'package:flutter/material.dart';

class WeatherModel {
  const WeatherModel({
    required this.cityName,
    required this.currentTemp,
    required this.condition,
    required this.windSpeed,
    required this.maxTemp,
    required this.minTemp,
    required this.dailyForecast,
    required this.hourlyForecast,
  });

  /// Open-Meteo forecast API 응답 파싱. 현재는 사용하지 않는 OpenMeteoWeatherRepository
  /// (기상청으로 교체됨, 추후 재사용 대비 보존) 전용이다.
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
        condition: WeatherCondition.fromWmoCode(weatherCodes[i].toInt()),
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
          condition: WeatherCondition.fromWmoCode(hourCodes[i].toInt()),
          isNow: time.hour == currentTime.hour,
        ));
      }
    }

    return WeatherModel(
      cityName: cityName,
      currentTemp: (current['temperature_2m'] as num).toDouble(),
      condition: WeatherCondition.fromWmoCode((current['weather_code'] as num).toInt()),
      windSpeed: (current['wind_speed_10m'] as num).toDouble(),
      maxTemp: dailyForecast.first.maxTemp,
      minTemp: dailyForecast.first.minTemp,
      dailyForecast: dailyForecast,
      hourlyForecast: hourlyForecast,
    );
  }

  final String cityName;
  final double currentTemp;
  final WeatherCondition condition;
  final double windSpeed;
  final num maxTemp;
  final num minTemp;

  /// 기상청 기준 오늘/내일/모레 3일치 일별 예보. (Open-Meteo 경로에서는 forecast_days만큼)
  final List<DailyForecast> dailyForecast;

  /// 현재 시각부터 24시간 후까지의 시간별 예보.
  final List<HourlyForecast> hourlyForecast;

  String get description => condition.description;
  IconData get icon => condition.icon;
}

class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.condition,
  });

  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final WeatherCondition condition;

  String get description => condition.description;
  IconData get icon => condition.icon;
}

class HourlyForecast {
  const HourlyForecast({
    required this.time,
    required this.temperature,
    required this.condition,
    required this.isNow,
  });

  final DateTime time;
  final double temperature;
  final WeatherCondition condition;

  /// 시간별 예보 중 현재 시각과 같은 시간대인지 여부.
  final bool isNow;

  String get description => condition.description;
  IconData get icon => condition.icon;
}

/// 날씨 상태. 데이터 소스(Open-Meteo의 WMO 코드, 기상청의 SKY/PTY 코드)가 서로 다른
/// 코드 체계를 쓰기 때문에, 각 리포지토리가 자신의 코드를 이 공통 조건으로 변환해서
/// WeatherModel에 담는다.
enum WeatherCondition {
  clear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  freezingDrizzle,
  rain,
  freezingRain,
  sleet,
  snow,
  snowGrains,
  showers,
  snowShowers,
  thunderstorm,
  thunderstormHail,
  unknown;

  /// WMO Weather interpretation codes (Open-Meteo). 현재 미사용 경로 전용으로 보존.
  factory WeatherCondition.fromWmoCode(int code) {
    switch (code) {
      case 0:
        return WeatherCondition.clear;
      case 1:
      case 2:
        return WeatherCondition.partlyCloudy;
      case 3:
        return WeatherCondition.cloudy;
      case 45:
      case 48:
        return WeatherCondition.fog;
      case 51:
      case 53:
      case 55:
        return WeatherCondition.drizzle;
      case 56:
      case 57:
        return WeatherCondition.freezingDrizzle;
      case 61:
      case 63:
      case 65:
        return WeatherCondition.rain;
      case 66:
      case 67:
        return WeatherCondition.freezingRain;
      case 71:
      case 73:
      case 75:
        return WeatherCondition.snow;
      case 77:
        return WeatherCondition.snowGrains;
      case 80:
      case 81:
      case 82:
        return WeatherCondition.showers;
      case 85:
      case 86:
        return WeatherCondition.snowShowers;
      case 95:
        return WeatherCondition.thunderstorm;
      case 96:
      case 99:
        return WeatherCondition.thunderstormHail;
      default:
        return WeatherCondition.unknown;
    }
  }

  /// 기상청 단기예보의 하늘상태(SKY: 1 맑음, 3 구름많음, 4 흐림)와
  /// 강수형태(PTY: 0 없음, 1 비, 2 비/눈, 3 눈, 4 소나기, 5~7은 초단기예보 전용 세분류)를
  /// 조건으로 변환한다. 강수가 있으면(PTY != 0) 하늘상태보다 강수형태를 우선한다.
  factory WeatherCondition.fromKmaSkyPty({required int sky, required int pty}) {
    switch (pty) {
      case 1:
      case 5:
        return WeatherCondition.rain;
      case 2:
      case 6:
        return WeatherCondition.sleet;
      case 3:
      case 7:
        return WeatherCondition.snow;
      case 4:
        return WeatherCondition.showers;
    }
    switch (sky) {
      case 1:
        return WeatherCondition.clear;
      case 3:
        return WeatherCondition.partlyCloudy;
      case 4:
        return WeatherCondition.cloudy;
      default:
        return WeatherCondition.unknown;
    }
  }

  String get description {
    switch (this) {
      case WeatherCondition.clear:
        return '맑음';
      case WeatherCondition.partlyCloudy:
        return '대체로 맑음';
      case WeatherCondition.cloudy:
        return '흐림';
      case WeatherCondition.fog:
        return '안개';
      case WeatherCondition.drizzle:
        return '이슬비';
      case WeatherCondition.freezingDrizzle:
        return '어는 이슬비';
      case WeatherCondition.rain:
        return '비';
      case WeatherCondition.freezingRain:
        return '어는 비';
      case WeatherCondition.sleet:
        return '비/눈';
      case WeatherCondition.snow:
        return '눈';
      case WeatherCondition.snowGrains:
        return '싸락눈';
      case WeatherCondition.showers:
        return '소나기';
      case WeatherCondition.snowShowers:
        return '눈 소나기';
      case WeatherCondition.thunderstorm:
        return '뇌우';
      case WeatherCondition.thunderstormHail:
        return '우박 동반 뇌우';
      case WeatherCondition.unknown:
        return '알 수 없음';
    }
  }

  IconData get icon {
    switch (this) {
      case WeatherCondition.clear:
        return Icons.wb_sunny;
      case WeatherCondition.partlyCloudy:
        return Icons.wb_cloudy;
      case WeatherCondition.cloudy:
        return Icons.cloud;
      case WeatherCondition.fog:
        return Icons.foggy;
      case WeatherCondition.drizzle:
      case WeatherCondition.freezingDrizzle:
        return Icons.water_drop_outlined;
      case WeatherCondition.rain:
      case WeatherCondition.freezingRain:
        return Icons.water_drop;
      case WeatherCondition.sleet:
      case WeatherCondition.snow:
      case WeatherCondition.snowGrains:
      case WeatherCondition.snowShowers:
        return Icons.ac_unit;
      case WeatherCondition.showers:
        return Icons.umbrella;
      case WeatherCondition.thunderstorm:
      case WeatherCondition.thunderstormHail:
        return Icons.thunderstorm;
      case WeatherCondition.unknown:
        return Icons.help_outline;
    }
  }
}
