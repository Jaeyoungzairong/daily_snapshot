import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/exchange_rate_provider.dart';
import '../data/currency_catalog.dart';
import '../data/exchange_rate_model.dart';

class ExchangeRateCard extends ConsumerStatefulWidget {
  const ExchangeRateCard({super.key});

  @override
  ConsumerState<ExchangeRateCard> createState() => _ExchangeRateCardState();
}

class _ExchangeRateCardState extends ConsumerState<ExchangeRateCard> with WidgetsBindingObserver {
  final TextEditingController _amountController = TextEditingController(text: '100');
  double _foreignAmount = 100;
  Timer? _refreshTimer;

  // 환율 데이터(FutureProvider)는 한 번 fetch되면 계속 캐시되어, 앱을 오래 켜둔 채로
  // 있으면 API가 그 사이 갱신되어도 화면은 옛날 값을 계속 보여준다. 이를 막기 위해
  // 앱이 포그라운드로 돌아올 때, 그리고 장시간 켜둔 경우를 대비해 주기적으로 재조회한다.
  static const _refreshInterval = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshRates());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRates();
    }
  }

  void _refreshRates() {
    ref.invalidate(latestRatesProvider);
    ref.invalidate(chartHistoryProvider(
      (ref.read(selectedCurrencyProvider), ref.read(chartPeriodProvider)),
    ));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.extension<AppAccentColors>()?.fx ?? theme.colorScheme.primary;
    final latestAsync = ref.watch(latestRatesProvider);
    final selectedCode = ref.watch(selectedCurrencyProvider);

    return DashboardCard(
      title: '환율',
      icon: Icons.currency_exchange,
      accentColor: accentColor,
      trailing: DropdownMenu<String>(
        initialSelection: selectedCode,
        // 필드 자체는 짧은 코드("USD") 기준으로 자동으로 좁게 잡히게 두고, 펼쳤을 때 나오는
        // 메뉴만 menuStyle로 따로 넓혀서 "USD · 미국 달러" 같은 전체 이름이 줄바꿈 없이 보이게 한다.
        textStyle: theme.textTheme.bodyMedium,
        menuStyle: const MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(190, 0)),
        ),
        trailingIcon: const Icon(Icons.expand_more, size: 20),
        selectedTrailingIcon: const Icon(Icons.expand_less, size: 20),
        dropdownMenuEntries: [
          for (final currency in CurrencyCatalog.targetCurrencies)
            DropdownMenuEntry(
              value: currency.code,
              label: currency.code,
              labelWidget: Text('${currency.code} · ${currency.displayName}'),
            ),
        ],
        onSelected: (value) {
          if (value == null) return;
          ref.read(selectedCurrencyProvider.notifier).select(value);
        },
      ),
      child: latestAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(latestRatesProvider),
        ),
        data: (rates) {
          final selectedRate = rates.firstWhere((r) => r.currency.code == selectedCode);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SelectedRateHeader(rate: selectedRate),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text('간단 환산', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _Converter(
                rate: selectedRate,
                controller: _amountController,
                foreignAmount: _foreignAmount,
                onChanged: (value) => setState(() => _foreignAmount = value),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text('환율 추이', style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              _RateHistoryChart(currencyCode: selectedCode, accentColor: accentColor),
            ],
          );
        },
      ),
    );
  }
}

class _SelectedRateHeader extends StatelessWidget {
  const _SelectedRateHeader({required this.rate});

  final CurrencyKrwRate rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitLabel = rate.currency.unit == 1 ? '1 ${rate.currency.code}' : '${rate.currency.unit} ${rate.currency.code}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '기준일: ${rate.date} · 원화(KRW) 기준',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$unitLabel (${rate.currency.displayName})',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            Text(
              '${Formatters.amount(rate.krwValue)}원',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }
}

class _Converter extends StatelessWidget {
  const _Converter({
    required this.rate,
    required this.controller,
    required this.foreignAmount,
    required this.onChanged,
  });

  final CurrencyKrwRate rate;
  final TextEditingController controller;
  final double foreignAmount;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final krwResult = foreignAmount / rate.currency.unit * rate.krwValue;
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(suffixText: rate.currency.code),
            onChanged: (value) => onChanged(double.tryParse(value) ?? 0),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_forward, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '${Formatters.amount(krwResult)}원',
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _RateHistoryChart extends ConsumerWidget {
  const _RateHistoryChart({required this.currencyCode, required this.accentColor});

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
              final labelInterval = (points.length / 4).ceilToDouble().clamp(1.0, double.infinity);
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
                            fontWeight: FontWeight.w700,
                          ),
                          children: [
                            TextSpan(
                              text: Formatters.shortDate(point.date),
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
                              Formatters.shortDate(points[index].date),
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
