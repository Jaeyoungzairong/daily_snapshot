import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/key_value_store.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  ThemeModeNotifier({this.initial = ThemeMode.dark, KeyValueStore? store}) : _providedStore = store;

  static const String _key = 'app_theme_mode';

  final ThemeMode initial;
  final KeyValueStore? _providedStore;
  KeyValueStore? _store;

  // toggle()이 실제로 호출될 때만 저장소를 생성한다: 위젯 테스트 중 이 notifier를
  // 오버라이드하지 않고 렌더링만 하는 경우, 플러그인이 초기화되지 않은 상태에서
  // SharedPreferencesAsync() 생성만으로 예외가 나는 것을 막기 위함.
  KeyValueStore get _resolvedStore => _store ??= _providedStore ?? SharedPreferencesKeyValueStore();

  /// 저장된 테마 모드를 앱 시작(runApp) 전에 미리 읽어온다. 저장된 값이 없으면 다크를
  /// 기본값으로 쓴다.
  static Future<ThemeMode> loadInitial([KeyValueStore? store]) async {
    final resolvedStore = store ?? SharedPreferencesKeyValueStore();
    final raw = await resolvedStore.getString(_key);
    return raw == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  @override
  ThemeMode build() => initial;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _resolvedStore.setString(_key, state == ThemeMode.dark ? 'dark' : 'light');
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
