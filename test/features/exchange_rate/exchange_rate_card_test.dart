import 'package:daily_snapshot/core/network/api_client.dart';
import 'package:daily_snapshot/features/exchange_rate/application/exchange_rate_provider.dart';
import 'package:daily_snapshot/features/exchange_rate/data/currency_catalog.dart';
import 'package:daily_snapshot/features/exchange_rate/data/exchange_rate_model.dart';
import 'package:daily_snapshot/features/exchange_rate/data/exchange_rate_repository.dart';
import 'package:daily_snapshot/features/exchange_rate/presentation/exchange_rate_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 조회 횟수·지연·실패를 제어할 수 있는 가짜 리포지토리.
class _FakeExchangeRateRepository extends ExchangeRateRepository {
  _FakeExchangeRateRepository({this.delay = Duration.zero});

  final Duration delay;
  int latestCount = 0;
  final List<String> historyCalls = [];
  bool latestFailing = false;
  bool historyFailing = false;

  @override
  Future<List<CurrencyKrwRate>> fetchLatestRates() async {
    latestCount++;
    final callNumber = latestCount;
    await Future<void>.delayed(delay);
    if (latestFailing) throw ApiException('서버 응답이 없습니다.');
    return [
      for (final currency in CurrencyCatalog.targetCurrencies)
        // 몇 번째 조회 결과인지 화면의 기준일로 알 수 있게 한다.
        CurrencyKrwRate(currency: currency, krwValue: 1400, date: '2026-09-$callNumber'),
    ];
  }

  @override
  Future<List<ExchangeRateHistoryPoint>> fetchRateHistory({
    required String currencyCode,
    required int days,
  }) async {
    historyCalls.add(currencyCode);
    await Future<void>.delayed(delay);
    if (historyFailing) throw ApiException('서버 응답이 없습니다.');
    return [
      for (var i = 0; i < 14; i++)
        ExchangeRateHistoryPoint(date: DateTime(2026, 9, 1 + i), krwValue: 1400.0 + i),
    ];
  }
}

Future<void> _pumpCard(WidgetTester tester, _FakeExchangeRateRepository repository) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [exchangeRateRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ExchangeRateCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 앱이 백그라운드로 갔다가 다시 보이게 된 상황(프레임워크가 허용하는 전이 순서).
Future<void> _backgroundThenResume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
}

const _failedLatest = '환율 갱신에 실패해 이전 데이터를 표시 중입니다.';
const _failedChart = '그래프 갱신에 실패해 이전 데이터를 표시 중입니다.';

void main() {
  testWidgets('refetches every hour and keeps the old data on screen meanwhile', (tester) async {
    // 조회에 2분이 걸리게 해서, 타이머가 돈 뒤 "받는 중"인 구간을 안정적으로 관찰한다. 그래프는
    // 최신 환율이 도착한 뒤에 받기 시작해서 첫 로딩이 끝나는 데 4분이 걸리고, 60분 타이머는
    // 그로부터 약 56분 뒤에 돈다.
    final repository = _FakeExchangeRateRepository(delay: const Duration(minutes: 2));
    await _pumpCard(tester, repository);
    expect(repository.latestCount, 1);
    expect(find.text('기준일: 2026-09-1 · 원화(KRW) 기준'), findsOneWidget);

    await tester.pump(const Duration(minutes: 55));
    expect(repository.latestCount, 1);

    await tester.pump(const Duration(seconds: 90));
    expect(repository.latestCount, 2);
    // 다시 받는 동안에도 스피너로 바뀌지 않고 이전 값이 그대로 보인다.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('기준일: 2026-09-1 · 원화(KRW) 기준'), findsOneWidget);

    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(find.text('기준일: 2026-09-2 · 원화(KRW) 기준'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // 예전엔 지금 보이는 (통화, 기간) 그래프만 갱신해서, 나중에 다른 통화를 고르면 옛날에 캐시된
  // 값이 그대로 나왔다.
  testWidgets('a refresh also drops cached charts of other currencies', (tester) async {
    final repository = _FakeExchangeRateRepository();
    await _pumpCard(tester, repository);
    final container = ProviderScope.containerOf(tester.element(find.byType(ExchangeRateCard)));

    container.read(selectedCurrencyProvider.notifier).select('CNY');
    await tester.pumpAndSettle();
    container.read(selectedCurrencyProvider.notifier).select('USD');
    await tester.pumpAndSettle();
    expect(repository.historyCalls, ['USD', 'CNY']);

    await tester.pump(const Duration(hours: 1));
    await tester.pumpAndSettle();
    // 지금 보이는 USD만 다시 받는다.
    expect(repository.historyCalls, ['USD', 'CNY', 'USD']);

    container.read(selectedCurrencyProvider.notifier).select('CNY');
    await tester.pumpAndSettle();
    expect(repository.historyCalls, ['USD', 'CNY', 'USD', 'CNY']);
  });

  testWidgets('keeps the last rates and says so when a refresh fails, then recovers', (
    tester,
  ) async {
    final repository = _FakeExchangeRateRepository();
    await _pumpCard(tester, repository);
    expect(find.text(_failedLatest), findsNothing);

    repository.latestFailing = true;
    repository.historyFailing = true;
    await tester.pump(const Duration(hours: 1));
    await tester.pumpAndSettle();

    // 멀쩡하던 카드가 에러 화면으로 바뀌지 않고, 마지막 값과 실패 사실을 함께 보여준다.
    expect(find.text('다시 시도'), findsNothing);
    expect(find.text('기준일: 2026-09-1 · 원화(KRW) 기준'), findsOneWidget);
    expect(find.text(_failedLatest), findsOneWidget);
    expect(find.text(_failedChart), findsOneWidget);

    repository.latestFailing = false;
    repository.historyFailing = false;
    await tester.pump(const Duration(hours: 1));
    await tester.pumpAndSettle();

    expect(find.text(_failedLatest), findsNothing);
    expect(find.text(_failedChart), findsNothing);
    expect(find.text('기준일: 2026-09-3 · 원화(KRW) 기준'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a first load that fails still shows the error screen', (tester) async {
    final repository = _FakeExchangeRateRepository()..latestFailing = true;
    await _pumpCard(tester, repository);

    expect(find.text('다시 시도'), findsOneWidget);
  });

  group('coming back to the app', () {
    testWidgets('does not refetch right after the data was loaded', (tester) async {
      final repository = _FakeExchangeRateRepository();
      await _pumpCard(tester, repository);

      await _backgroundThenResume(tester);
      await tester.pumpAndSettle();

      expect(repository.latestCount, 1);
    });

    testWidgets('retries right away when the last refresh had failed', (tester) async {
      final repository = _FakeExchangeRateRepository();
      await _pumpCard(tester, repository);
      repository.latestFailing = true;
      await tester.pump(const Duration(hours: 1));
      await tester.pumpAndSettle();
      expect(repository.latestCount, 2);

      repository.latestFailing = false;
      await _backgroundThenResume(tester);
      await tester.pumpAndSettle();

      expect(repository.latestCount, 3);
      expect(find.text(_failedLatest), findsNothing);
    });
  });
}
