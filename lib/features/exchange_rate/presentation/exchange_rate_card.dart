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
  // 최신 환율(open.er-api.com)은 하루 한 번, 그래프(Frankfurter/ECB)는 영업일에만 바뀌어서
  // 자주 부를 이유가 없다 — 1시간이면 충분하다.
  //
  // 탭/앱으로 돌아왔을 때도 같은 기준을 쓴다: 마지막 갱신이 이 주기보다 오래됐을 때만 다시
  // 받는다(웹은 다른 창을 눌렀다 돌아오는 것만으로도 "복귀"라, 기준이 짧으면 창을 오갈 때마다
  // API를 부르게 된다). 직전 갱신이 실패했으면 이 기준과 무관하게 바로 재시도한다.
  static const _refreshInterval = Duration(minutes: 60);

  // 처음 화면이 뜰 때 데이터를 받아오므로 그 시점을 마지막 갱신으로 본다.
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshRates());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final failed = ref.read(latestRatesProvider).hasError;
    if (!failed && DateTime.now().difference(_lastRefresh) < _refreshInterval) return;
    _refreshRates();
  }

  // 화면에는 이전 값을 그대로 두고(build/RateHistoryChart의 skipLoadingOnReload/skipError) 뒤에서
  // 다시 받는다. 그래프는 선택한 (통화, 기간) 하나만이 아니라 family 전체를 무효화한다 — 예전엔
  // 지금 보이는 조합만 갱신해서, 나중에 다른 통화/기간을 고르면 옛날에 캐시된 값이 그대로 나왔다.
  void _refreshRates() {
    _lastRefresh = DateTime.now();
    ref.invalidate(latestRatesProvider);
    ref.invalidate(chartHistoryProvider);
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
        // 갱신 중이거나 갱신에 실패해도 이미 받아 둔 값이 있으면 그대로 보여준다(스피너/에러
        // 화면으로 바뀌지 않게). 처음 조회가 실패했을 때만 에러 화면.
        skipLoadingOnReload: true,
        skipError: true,
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
              _SelectedRateHeader(rate: selectedRate, refreshFailed: latestAsync.hasError),
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
  const _SelectedRateHeader({required this.rate, required this.refreshFailed});

  final CurrencyKrwRate rate;

  /// 자동 갱신에 실패해 이전에 받아 둔 값을 보여주는 중인지.
  final bool refreshFailed;

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
        if (refreshFailed)
          Text(
            '환율 갱신에 실패해 이전 데이터를 표시 중입니다.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
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
