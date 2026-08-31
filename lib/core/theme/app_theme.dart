import 'package:flutter/material.dart';

/// 카드별 포인트 컬러(날씨=앰버, 환율=틸)를 라이트/다크 테마에 맞춰 제공한다.
@immutable
class AppAccentColors extends ThemeExtension<AppAccentColors> {
  const AppAccentColors({
    required this.weather,
    required this.fx,
    required this.todo,
    required this.shortcuts,
  });

  final Color weather;
  final Color fx;
  final Color todo;
  final Color shortcuts;

  @override
  AppAccentColors copyWith({Color? weather, Color? fx, Color? todo, Color? shortcuts}) {
    return AppAccentColors(
      weather: weather ?? this.weather,
      fx: fx ?? this.fx,
      todo: todo ?? this.todo,
      shortcuts: shortcuts ?? this.shortcuts,
    );
  }

  @override
  AppAccentColors lerp(ThemeExtension<AppAccentColors>? other, double t) {
    if (other is! AppAccentColors) return this;
    return AppAccentColors(
      weather: Color.lerp(weather, other.weather, t)!,
      fx: Color.lerp(fx, other.fx, t)!,
      todo: Color.lerp(todo, other.todo, t)!,
      shortcuts: Color.lerp(shortcuts, other.shortcuts, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF5B5FEF);

  static const _weatherAccentLight = Color(0xFFB45F06);
  static const _fxAccentLight = Color(0xFF0F6E56);
  static const _todoAccentLight = Color(0xFF534AB7);
  static const _shortcutsAccentLight = Color(0xFF185FA5);
  static const _weatherAccentDark = Color(0xFFF0997B);
  static const _fxAccentDark = Color(0xFF5DCAA5);
  static const _todoAccentDark = Color(0xFFAFA9EC);
  static const _shortcutsAccentDark = Color(0xFF85B7EB);

  static ThemeData get light => _themeFrom(
        ColorScheme.fromSeed(seedColor: _seedColor),
        const AppAccentColors(
          weather: _weatherAccentLight,
          fx: _fxAccentLight,
          todo: _todoAccentLight,
          shortcuts: _shortcutsAccentLight,
        ),
      );

  static ThemeData get dark => _themeFrom(
        ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
        const AppAccentColors(
          weather: _weatherAccentDark,
          fx: _fxAccentDark,
          todo: _todoAccentDark,
          shortcuts: _shortcutsAccentDark,
        ),
      );

  static ThemeData _themeFrom(ColorScheme colorScheme, AppAccentColors accentColors) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surfaceContainerLowest,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      extensions: [accentColors],
    );
  }
}
