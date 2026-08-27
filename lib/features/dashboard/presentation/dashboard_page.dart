import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_mode_provider.dart';
import '../../exchange_rate/presentation/exchange_rate_card.dart';
import '../../stock/presentation/stock_placeholder_card.dart';
import '../../weather/presentation/weather_card.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const double _wideBreakpoint = 900;
  static const List<Widget> _cards = [
    WeatherCard(),
    ExchangeRateCard(),
    StockPlaceholderCard(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather & FX Dashboard'),
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: isWide ? _buildGrid() : _buildColumn(),
              ),
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
