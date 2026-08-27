import 'package:flutter/material.dart';

import '../../../core/widgets/dashboard_card.dart';

/// 2단계 확장 자리. 실제 주식 데이터 연동 전까지 레이아웃만 확보한다.
class StockPlaceholderCard extends StatelessWidget {
  const StockPlaceholderCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DashboardCard(
      title: '주식',
      icon: Icons.show_chart,
      child: SizedBox(
        height: 120,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, color: theme.colorScheme.outline),
              const SizedBox(height: 8),
              Text(
                'Coming soon',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
