import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/numeric_input_formatter.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/exchange_rate_provider.dart';
import '../data/currency_catalog.dart';
import '../data/exchange_rate_model.dart';
import 'rate_history_chart.dart';

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
    ref.invalidate(
      chartHistoryProvider((ref.read(selectedCurrencyProvider), ref.read(chartPeriodProvider))),
    );
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
        // 통화 목록에서 고르기만 하면 되므로 텍스트 입력(키보드/필터링)은 막아 순수 선택
        // 드롭다운처럼 동작하게 한다.
        requestFocusOnTap: false,
        enableFilter: false,
        enableSearch: false,
        // 필드 자체는 짧은 코드("USD") 기준으로 자동으로 좁게 잡히게 두고, 펼쳤을 때 나오는
        // 메뉴만 menuStyle로 따로 넓혀서 "USD · 미국 달러" 같은 전체 이름이 줄바꿈 없이 보이게 한다.
        textStyle: theme.textTheme.bodyMedium,
        menuStyle: const MenuStyle(minimumSize: WidgetStatePropertyAll(Size(190, 0))),
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
              RateHistoryChart(currencyCode: selectedCode, accentColor: accentColor),
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
    final unitLabel = rate.currency.unit == 1
        ? '1 ${rate.currency.code}'
        : '${rate.currency.unit} ${rate.currency.code}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('기준일: ${rate.date} · 원화(KRW) 기준', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$unitLabel (${rate.currency.displayName})', style: theme.textTheme.bodyLarge),
            const Spacer(),
            Text(
              '${Formatters.amount(rate.krwValue)}원',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
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
            keyboardType: TextInputType.text,
            inputFormatters: [NumericInputFormatter()],
            decoration: InputDecoration(suffixText: rate.currency.code),
            onChanged: (value) => onChanged(double.tryParse(value) ?? 0),
          ),
        ),
        const SizedBox(width: 12),
        const Icon(Icons.arrow_forward, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text('${Formatters.amount(krwResult)}원', style: theme.textTheme.bodyLarge)),
      ],
    );
  }
}
