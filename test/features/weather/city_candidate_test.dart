import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CityCandidate', () {
    test('fromJson parses Open-Meteo geocoding result', () {
      final json = {
        'name': 'Anyang-si',
        'latitude': 37.3925,
        'longitude': 126.92694,
        'admin1': 'Gyeonggi-do',
        'country': 'South Korea',
        'population': 595644,
      };

      final candidate = CityCandidate.fromJson(json);

      expect(candidate.name, 'Anyang-si');
      expect(candidate.latitude, 37.3925);
      expect(candidate.longitude, 126.92694);
      expect(candidate.admin1, 'Gyeonggi-do');
      expect(candidate.country, 'South Korea');
      expect(candidate.population, 595644);
    });

    test('fromJson leaves population null when the field is absent', () {
      final json = {
        'name': 'Anyang-dong',
        'latitude': 35.7193,
        'longitude': 127.05194,
      };

      final candidate = CityCandidate.fromJson(json);

      expect(candidate.population, isNull);
    });

    test('displayLabel joins name, admin1, and country', () {
      const candidate = CityCandidate(
        name: 'Anyang',
        latitude: 36.096,
        longitude: 114.38278,
        admin1: 'Henan',
        country: '중국',
      );

      expect(candidate.displayLabel, 'Anyang, Henan, 중국');
    });

    test('two candidates with the same name but different coordinates are not equal', () {
      const korea = CityCandidate(name: 'Anyang', latitude: 37.3925, longitude: 126.92694);
      const china = CityCandidate(name: 'Anyang', latitude: 36.096, longitude: 114.38278);

      expect(korea == china, isFalse);
    });
  });
}
