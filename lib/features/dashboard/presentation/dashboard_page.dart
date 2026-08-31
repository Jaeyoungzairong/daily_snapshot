import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/local_config.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../exchange_rate/presentation/exchange_rate_card.dart';
import '../../shortcuts/presentation/shortcuts_card.dart';
import '../../todo/presentation/todo_card.dart';
import '../../weather/presentation/weather_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const double _wideBreakpoint = 900;
  static const List<Widget> _cards = [
    WeatherCard(),
    ShortcutsCard(),
    ExchangeRateCard(),
    TodoCard(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/images/app_icon.png', width: 28, height: 28),
            ),
            const SizedBox(width: 10),
            const Text('데일리 스냅샷'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isDark ? '라이트 테마로 전환' : '다크 테마로 전환',
            icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: isWide ? _buildGrid() : _buildColumn(),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'v${LocalConfig.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGrid() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: _cards
          .map((card) => SizedBox(width: 560, child: card))
          .toList(),
    );
  }

  Widget _buildColumn() {
    return Column(
      children: [
        for (final card in _cards) ...[
          card,
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
