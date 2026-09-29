import 'package:daily_snapshot/core/data/key_value_store.dart';
import 'package:daily_snapshot/core/theme/theme_mode_provider.dart';
import 'package:daily_snapshot/features/weather/application/weather_provider.dart';
import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 읽기/쓰기가 모두 실패하는 저장소(플러그인 오류, 저장소 접근 불가 상황 재현용).
class _BrokenStore implements KeyValueStore {
  @override
  Future<String?> getString(String key) async => throw Exception('read failed');

  @override
  Future<void> setString(String key, String value) async => throw Exception('write failed');

  @override
  Future<void> remove(String key) async => throw Exception('remove failed');
}

void main() {
  group('ThemeModeNotifier', () {
    test('loadInitial falls back to dark when the store cannot be read', () async {
      expect(await ThemeModeNotifier.loadInitial(_BrokenStore()), ThemeMode.dark);
    });

    test('toggle() still flips the theme when persisting fails', () async {
      final container = ProviderContainer(
        overrides: [
          themeModeProvider.overrideWith(() => ThemeModeNotifier(store: _BrokenStore())),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.dark);
      container.read(themeModeProvider.notifier).toggle();
      // 저장 실패가 처리되지 않은 예외로 새지 않는지 확인하기 위해 이벤트 루프를 한 번 돈다.
      await Future<void>.delayed(Duration.zero);

      expect(container.read(themeModeProvider), ThemeMode.light);
    });
  });

  group('SelectedCityNotifier', () {
    test('loadInitial falls back to the default city when the store cannot be read', () async {
      final city = await SelectedCityNotifier.loadInitial(_BrokenStore());

      expect(city.name, '서울특별시');
    });

    test('select() still updates the city when persisting fails', () async {
      final container = ProviderContainer(
        overrides: [
          selectedCityProvider.overrideWith(() => SelectedCityNotifier(store: _BrokenStore())),
        ],
      );
      addTearDown(container.dispose);
      const busan = CityCandidate(name: '부산광역시', latitude: 35.1796, longitude: 129.0756);

      container.read(selectedCityProvider.notifier).select(busan);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(selectedCityProvider).name, '부산광역시');
    });
  });
}
