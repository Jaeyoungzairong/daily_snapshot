import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/exchange_rate_provider.dart';

class RateHistoryChart extends ConsumerWidget {
  const RateHistoryChart({super.key, required this.currencyCode, required this.accentColor});

  final String currencyCode;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedPeriod = ref.watch(chartPeriodProvider);
    final args = (currencyCode, selectedPeriod);
    final historyAsync = ref.watch(chartHistoryProvider(args));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in ChartPeriod.values)
              ChoiceChip(
                label: Text(period.label),
                selected: selectedPeriod == period,
                onSelected: (_) => ref.read(chartPeriodProvider.notifier).select(period),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 300,
          child: historyAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(chartHistoryProvider(args)),
            ),
            data: (points) {
              if (points.isEmpty) {
                return const Center(child: Text('표시할 데이터가 없습니다.'));
              }

              final values = points.map((p) => p.krwValue);
              final minValue = values.reduce((a, b) => a < b ? a : b);
              final maxValue = values.reduce((a, b) => a > b ? a : b);
              // 정수로 올림한 간격을 쓰면 (points.length - 1)이 그 간격의 배수가 아닐 때
              // 마지막 눈금이 끝까지 못 미쳐서 라벨들이 오른쪽으로 치우친 여백을 남긴 채
              // 왼쪽에 몰려 보인다. 소수 간격을 그대로 써서 마지막 눈금이 항상 마지막
              // 데이터 지점(points.length - 1)에 정확히 오도록 한다.
              final labelInterval = ((points.length - 1) / 4).clamp(1.0, double.infinity);
              final axisLabel = _axisLabelFormatterFor(selectedPeriod);
              // 그리드 간격을 "딱 떨어지는" 숫자(1/2/5 x 10^n)로 잡는다. range/4 같은 임의 값을 쓰면
              // 맨 위 그리드선이 maxY와 거의 같은 위치에 찍혀서, 실제 최댓값 라벨과 겹쳐 보였다.
              final gridInterval = _niceInterval(maxValue - minValue);
              // minY/maxY 자체도 gridInterval의 배수로 반올림한다. 그러면 축 경계가 곧 그리드선
              // 위치와 정확히 일치해서, "실제 최솟값/최댓값" 라벨을 별도로 안 그려도 축 맨 위·아래
              // 눈금이 자연스럽게 그 역할을 하고, 두 라벨 체계가 겹칠 일도 없어진다.
              final niceMinY = (minValue / gridInterval).floor() * gridInterval;
              final niceMaxY = (maxValue / gridInterval).ceil() * gridInterval;

              return LineChart(
                LineChartData(
                  minY: niceMinY,
                  maxY: niceMaxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: gridInterval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    getTouchedSpotIndicator: (barData, spotIndexes) {
                      return spotIndexes.map((_) {
                        return TouchedSpotIndicatorData(
                          FlLine(
                            color: accentColor.withValues(alpha: 0.4),
                            strokeWidth: 2,
                            dashArray: [6, 4],
                          ),
                          FlDotData(
                            show: true,
                            getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                              radius: 6,
                              color: theme.colorScheme.surface,
                              strokeColor: accentColor,
                              strokeWidth: 3,
                            ),
                          ),
                        );
                      }).toList();
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                      tooltipBorderRadius: BorderRadius.circular(12),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      getTooltipItems: (spots) => spots.map((spot) {
                        final point = points[spot.x.round().clamp(0, points.length - 1)];
                        return LineTooltipItem(
                          '${Formatters.amount(point.krwValue)}원\n',
                          TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          children: [
                            TextSpan(
                              text: Formatters.fullDate(point.date),
                              style: TextStyle(
                                color: theme.colorScheme.onInverseSurface.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 52,
                        interval: gridInterval,
                        // minY/maxY가 이미 gridInterval의 배수로 반올림돼 있어서(위 참고), 여기서
                        // minIncluded/maxIncluded를 켜도 "정확한 경계값" 라벨이 일반 interval 눈금과
                        // 정확히 같은 위치·같은 값으로 겹치기만 할 뿐이라 안전하다. 그리고 이걸 켜야
                        // 축 맨 위/아래 라벨이 실제로 그려진다(꺼두면 경계 눈금 자체가 안 나온다).
                        getTitlesWidget: (value, meta) => Text(
                          Formatters.amount(value),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: labelInterval,
                        getTitlesWidget: (value, meta) {
                          final index = value.round().clamp(0, points.length - 1);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              axisLabel(points[index].date),
                              style: theme.textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].krwValue),
                      ],
                      isCurved: true,
                      curveSmoothness: 0.2,
                      color: accentColor,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: accentColor.withValues(alpha: 0.12)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 차트 축 눈금은 기간과 무관하게 항상 4~5개뿐이라(points.length / 4), 기간이 길수록
/// 눈금 하나가 담당하는 시간 폭도 넓어진다. 그 폭에 맞는 단위(일/월/년)로 라벨을 보여준다.
String Function(DateTime) _axisLabelFormatterFor(ChartPeriod period) {
  switch (period) {
    case ChartPeriod.fourteenDays:
    case ChartPeriod.oneMonth:
      return Formatters.shortDate;
    case ChartPeriod.sixMonths:
    case ChartPeriod.oneYear:
      return Formatters.monthLabel;
    case ChartPeriod.fiveYears:
    case ChartPeriod.tenYears:
      return Formatters.yearLabel;
  }
}

/// range를 대략 4등분하되, 결과를 1/2/5 x 10^n 중 가장 가까운 "딱 떨어지는" 값으로 반올림한다.
/// 그리드선과 축 라벨이 1,150.37 같은 어정쩡한 값 대신 1,200처럼 깔끔한 값에 찍히게 하기 위함.
double _niceInterval(double range) {
  if (range <= 0) return 1;
  final rawStep = range / 4;
  final magnitude = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final residual = rawStep / magnitude;
  final double niceResidual;
  if (residual > 5) {
    niceResidual = 10;
  } else if (residual > 2) {
    niceResidual = 5;
  } else if (residual > 1) {
    niceResidual = 2;
  } else {
    niceResidual = 1;
  }
  return niceResidual * magnitude;
}
