import 'package:flutter/material.dart';

/// 카드별 포인트 컬러(날씨=앰버, 환율=틸)를 라이트/다크 테마에 맞춰 제공한다.
@immutable
class AppAccentColors extends ThemeExtension<AppAccentColors> {
  const AppAccentColors({
    required this.weather,
    required this.fx,
    required this.todo,
    required this.memo,
    required this.shortcuts,
    required this.files,
  });

  final Color weather;
  final Color fx;
  final Color todo;
  final Color memo;
  final Color shortcuts;
  final Color files;

  @override
  AppAccentColors copyWith({
    Color? weather,
    Color? fx,
    Color? todo,
    Color? memo,
    Color? shortcuts,
    Color? files,
  }) {
    return AppAccentColors(
      weather: weather ?? this.weather,
      fx: fx ?? this.fx,
      todo: todo ?? this.todo,
      memo: memo ?? this.memo,
      shortcuts: shortcuts ?? this.shortcuts,
      files: files ?? this.files,
    );
  }

  @override
  AppAccentColors lerp(ThemeExtension<AppAccentColors>? other, double t) {
    if (other is! AppAccentColors) return this;
    return AppAccentColors(
      weather: Color.lerp(weather, other.weather, t)!,
      fx: Color.lerp(fx, other.fx, t)!,
      todo: Color.lerp(todo, other.todo, t)!,
      memo: Color.lerp(memo, other.memo, t)!,
      shortcuts: Color.lerp(shortcuts, other.shortcuts, t)!,
      files: Color.lerp(files, other.files, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF5B5FEF);

  static const _weatherAccentLight = Color(0xFFB45F06);
  static const _fxAccentLight = Color(0xFF0F6E56);
  static const _todoAccentLight = Color(0xFF534AB7);
  static const _memoAccentLight = Color(0xFF993556);
  static const _shortcutsAccentLight = Color(0xFF185FA5);
  static const _filesAccentLight = Color(0xFF2E7D45);
  static const _weatherAccentDark = Color(0xFFF0997B);
  static const _fxAccentDark = Color(0xFF5DCAA5);
  static const _todoAccentDark = Color(0xFFAFA9EC);
  static const _memoAccentDark = Color(0xFFED93B1);
  static const _shortcutsAccentDark = Color(0xFF85B7EB);
  static const _filesAccentDark = Color(0xFF83D89B);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor);
    return _themeFrom(
      colorScheme,
      const AppAccentColors(
        weather: _weatherAccentLight,
        fx: _fxAccentLight,
        todo: _todoAccentLight,
        memo: _memoAccentLight,
        shortcuts: _shortcutsAccentLight,
        files: _filesAccentLight,
      ),
      // 카드가 도드라져 보이도록 배경은 은은하게 톤을 주고, 카드는 순백으로 고정한다.
      backgroundColor: colorScheme.surfaceContainer,
      cardColor: colorScheme.surfaceContainerLowest,
    );
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark);
    return _themeFrom(
      colorScheme,
      const AppAccentColors(
        weather: _weatherAccentDark,
        fx: _fxAccentDark,
        todo: _todoAccentDark,
        memo: _memoAccentDark,
        shortcuts: _shortcutsAccentDark,
        files: _filesAccentDark,
      ),
      // 다크모드는 기존 색감(배경/카드 모두 낮은 톤)을 유지한다.
      // Card 위젯의 M3 기본 색상은 surface가 아니라 surfaceContainerLow.
      backgroundColor: colorScheme.surfaceContainerLowest,
      cardColor: colorScheme.surfaceContainerLow,
    );
  }

  static ThemeData _themeFrom(
    ColorScheme colorScheme,
    AppAccentColors accentColors, {
    required Color backgroundColor,
    required Color cardColor,
  }) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(elevation: 1, margin: EdgeInsets.zero, color: cardColor),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      extensions: [accentColors],
    );
  }
}
