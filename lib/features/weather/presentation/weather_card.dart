import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/weather_provider.dart';
import '../data/city_candidate.dart';
import '../data/weather_model.dart';
import '../util/location_service.dart';

class WeatherCard extends ConsumerStatefulWidget {
  const WeatherCard({super.key});

  @override
  ConsumerState<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends ConsumerState<WeatherCard> with WidgetsBindingObserver {
  late final TextEditingController _controller;
  Timer? _debounce;
  Timer? _refreshTimer;
  String _query = '';
  bool _locating = false;

  // 날씨(FutureProvider)는 한 번 조회하면 계속 캐시돼서, 아침에 열어 둔 탭은 종일 그때 기온과
  // 시간별 예보("지금" 표시, 지난 시간대)를 보여줬다. 시간별 예보의 "지금"/지난 시간 판단도
  // 조회 시점의 시각으로 한 번만 계산되므로 다시 조회해야만 갱신된다. 기상청 초단기실황은
  // 매시 40분경, 단기예보는 3시간마다 나와서 15분처럼 자주 불러도 대부분 같은 값이다 — 30분이면
  // 새 값이 나온 뒤 늦어도 30분 안에 화면에 반영된다.
  //
  // 탭/앱으로 돌아왔을 때도 같은 기준을 쓴다: 마지막 조회가 이 주기보다 오래됐을 때만 갱신한다
  // (웹은 다른 창을 눌렀다 돌아오는 것만으로도 "복귀"라, 기준이 짧으면 창을 오갈 때마다 기상청
  // API를 부르게 된다). 조회에 실패해 값이 없거나 옛 값이면 자연히 이 기준을 넘어 바로 재시도한다.
  static const Duration _refreshInterval = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(selectedCityProvider).name);
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshWeather());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final current = ref.read(weatherProvider(ref.read(selectedCityProvider)));
    if (current.isLoading) return;
    final fetchedAt = current.value?.fetchedAt;
    if (fetchedAt != null && DateTime.now().difference(fetchedAt) < _refreshInterval) return;
    _refreshWeather();
  }

  // 화면에는 이전 값을 그대로 두고(build의 skipLoadingOnReload/skipError) 뒤에서 다시 받는다.
  void _refreshWeather() {
    ref.invalidate(weatherProvider(ref.read(selectedCityProvider)));
  }

  // 기상청 지역 목록은 앱에 내장된 자산이라 매 키 입력마다 검색해도 부담이 없지만,
  // 빠르게 타이핑할 때 결과 목록이 매 글자마다 리빌드되며 깜빡이는 걸 막기 위해
  // 짧은 디바운스만 둔다(네트워크 지연과는 무관).
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _selectCity(CityCandidate city) {
    _debounce?.cancel();
    ref.read(selectedCityProvider.notifier).select(city);
    setState(() {
      _query = '';
      _controller.text = city.name;
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final position = await getCurrentPosition();
      final city = await ref
          .read(weatherRepositoryProvider)
          .nearestCity(position.latitude, position.longitude);
      if (!mounted) return;
      if (city == null) {
        _showMessage('한반도 인근 위치만 지원합니다.');
      } else {
        _selectCity(city);
      }
    } on LocationException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (_) {
      if (mounted) _showMessage('위치 정보를 가져올 수 없습니다.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = ref.watch(selectedCityProvider);
    final weatherAsync = ref.watch(weatherProvider(selectedCity));

    return DashboardCard(
      title: '날씨',
      icon: Icons.wb_sunny_outlined,
      accentColor: Theme.of(context).extension<AppAccentColors>()?.weather,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: '도시 이름',
              //hintText: '예: Seoul, Anyang, Paris',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _locating ? null : _useMyLocation,
                tooltip: '내 위치로 찾기',
                icon: _locating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
            onChanged: _onQueryChanged,
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CitySearchResults(query: _query, onSelect: _selectCity),
          ],
          const SizedBox(height: 16),
          weatherAsync.when(
            // 자동 갱신 중이거나 갱신에 실패해도 이미 받아 둔 값이 있으면 그대로 보여준다 —
            // 스피너로 바뀌거나 멀쩡한 날씨 화면이 에러 화면으로 바뀌는 것을 막는다(처음 조회하는
            // 도시는 이전 값이 없으므로 그대로 로딩/에러 화면).
            skipLoadingOnReload: true,
            skipError: true,
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(weatherProvider(selectedCity)),
            ),
            data: (weather) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(weather.cityName, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    const SizedBox(width: 8),
                    _FetchedAtLabel(
                      fetchedAt: weather.fetchedAt,
                      refreshFailed: weatherAsync.hasError,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(weather.icon, size: 40),
                    const SizedBox(width: 12),
                    Text(
                      Formatters.temperature(weather.currentTemp),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Text(weather.description, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '최고 ${Formatters.temperature(weather.maxTemp.toDouble())} · '
                  '최저 ${Formatters.temperature(weather.minTemp.toDouble())}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  weather.precipitationAmount == null
                      ? '풍속 ${weather.windSpeed.toStringAsFixed(1)} m/s'
                      : '풍속 ${weather.windSpeed.toStringAsFixed(1)} m/s · 강수량 ${weather.precipitationAmount}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text('시간별 예보', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _HourlyForecastRow(hourlyForecast: weather.hourlyForecast),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text('주간 예보', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _WeeklyForecastRow(dailyForecast: weather.dailyForecast),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 이 화면의 날씨를 서버에서 받아온 시각. 자동 갱신이 실패해 옛 값을 보여주는 중이면 그 사실도
/// 함께 알린다.
class _FetchedAtLabel extends StatelessWidget {
  const _FetchedAtLabel({required this.fetchedAt, required this.refreshFailed});

  final DateTime fetchedAt;
  final bool refreshFailed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = Formatters.time(fetchedAt);
    return Text(
      refreshFailed ? '갱신 실패 · $time 기준' : '$time 기준',
      style: theme.textTheme.bodySmall?.copyWith(
        color: refreshFailed ? theme.colorScheme.error : theme.colorScheme.outline,
      ),
    );
  }
}

class _WeeklyForecastRow extends StatelessWidget {
  const _WeeklyForecastRow({required this.dailyForecast});

  final List<DailyForecast> dailyForecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dailyForecast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final day = dailyForecast[index];
          final label = index == 0 ? '오늘' : Formatters.weekday(day.date);
          return SizedBox(
            width: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                Text(
                  Formatters.shortDate(day.date),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(day.icon, size: 22),
                const SizedBox(height: 4),
                Text(Formatters.temperature(day.maxTemp), style: theme.textTheme.labelMedium),
                Text(
                  Formatters.temperature(day.minTemp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (day.precipitationProbability > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${day.precipitationProbability}%',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HourlyForecastRow extends StatelessWidget {
  const _HourlyForecastRow({required this.hourlyForecast});

  final List<HourlyForecast> hourlyForecast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (hourlyForecast.isEmpty) {
      return Text(
        '오늘 남은 시간별 예보가 없습니다.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hourlyForecast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final hour = hourlyForecast[index];
          final label = hour.isNow ? '지금' : Formatters.hour24(hour.time);
          return SizedBox(
            width: 52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: hour.isNow ? theme.colorScheme.primary : null,
                    fontWeight: hour.isNow ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: 6),
                Icon(hour.icon, size: 20),
                const SizedBox(height: 6),
                Text(Formatters.temperature(hour.temperature), style: theme.textTheme.labelMedium),
                if (hour.precipitationProbability > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${hour.precipitationProbability}%',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
                if (hour.precipitationAmount != null)
                  Text(
                    hour.precipitationAmount!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CitySearchResults extends ConsumerWidget {
  const _CitySearchResults({required this.query, required this.onSelect});

  final String query;
  final ValueChanged<CityCandidate> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(citySearchProvider(query));
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      constraints: const BoxConstraints(maxHeight: 220),
      child: resultsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('검색 실패: $error', style: theme.textTheme.bodyMedium),
        ),
        data: (results) {
          if (results.isEmpty) {
            return const Padding(padding: EdgeInsets.all(16), child: Text('검색 결과가 없습니다.'));
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final candidate = results[index];
              return ListTile(
                dense: true,
                title: Text(candidate.name),
                subtitle: Text(
                  [
                    candidate.admin1,
                    candidate.country,
                  ].where((e) => e != null && e.isNotEmpty).join(', '),
                ),
                onTap: () => onSelect(candidate),
              );
            },
          );
        },
      ),
    );
  }
}
