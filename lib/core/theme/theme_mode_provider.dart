import 'dart:async';

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

  /// 저장된 테마 모드를 앱 시작(runApp) 전에 미리 읽어온다. 저장된 값이 없거나 저장소를
  /// 읽을 수 없으면(플러그인 오류 등) 다크를 기본값으로 쓴다 — 이 함수는 main()에서
  /// runApp 전에 await되므로, 여기서 예외가 새면 앱이 아예 시작되지 못한다.
  static Future<ThemeMode> loadInitial([KeyValueStore? store]) async {
    try {
      final resolvedStore = store ?? SharedPreferencesKeyValueStore();
      final raw = await resolvedStore.getString(_key);
      return raw == 'light' ? ThemeMode.light : ThemeMode.dark;
    } catch (_) {
      return ThemeMode.dark;
    }
  }

  @override
  ThemeMode build() => initial;

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    unawaited(_persist(state));
  }

  // 저장에 실패해도 화면의 테마는 이미 바뀌었고 다음 실행 때 기본값으로 돌아갈 뿐이라,
  // 사용자에게 알릴 만한 일이 아니다 — 처리되지 않은 Future 오류로 남지 않게만 삼킨다.
  Future<void> _persist(ThemeMode mode) async {
    try {
      await _resolvedStore.setString(_key, mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
