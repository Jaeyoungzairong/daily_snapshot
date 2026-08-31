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

class _WeatherCardState extends ConsumerState<WeatherCard> {
  late final TextEditingController _controller;
  Timer? _debounce;
  String _query = '';
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(selectedCityProvider).name);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
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
            _CitySearchResults(
              query: _query,
              onSelect: _selectCity,
            ),
          ],
          const SizedBox(height: 16),
          weatherAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate(weatherProvider(selectedCity)),
            ),
            data: (weather) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weather.cityName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(weather.icon, size: 40),
                    const SizedBox(width: 12),
                    Text(
                      Formatters.temperature(weather.currentTemp),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      weather.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
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
                    fontWeight: hour.isNow ? FontWeight.bold : null,
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
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text('검색 결과가 없습니다.'),
            );
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
                  [candidate.admin1, candidate.country]
                      .where((e) => e != null && e.isNotEmpty)
                      .join(', '),
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
