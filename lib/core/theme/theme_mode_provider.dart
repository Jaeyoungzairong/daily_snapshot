import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // 기본 테마를 다크로 고정. 원래는 최초 진입 시 시스템 설정을 따랐는데(아래),
    // 시스템 설정 대신 다크를 기본값으로 쓰기로 함. 되돌리려면 아래 두 줄의 주석을 해제하고
    // `return ThemeMode.dark;`를 지우면 된다. (import 'package:flutter/scheduler.dart'; 필요)
    // final isSystemDark = SchedulerBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    // return isSystemDark ? ThemeMode.dark : ThemeMode.light;
    return ThemeMode.dark;
  }

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
