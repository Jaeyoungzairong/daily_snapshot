import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/weather_provider.dart';
import '../data/city_candidate.dart';
import '../data/weather_model.dart';

class WeatherCard extends ConsumerStatefulWidget {
  const WeatherCard({super.key});

  @override
  ConsumerState<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends ConsumerState<WeatherCard> {
  late final TextEditingController _controller;
  String? _pendingSearch;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(selectedCityProvider).name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _pendingSearch = value);
  }

  void _selectCity(CityCandidate city) {
    ref.read(selectedCityProvider.notifier).select(city);
    setState(() {
      _pendingSearch = null;
      _controller.text = city.name;
    });
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: '도시 이름',
                    hintText: '예: Seoul, Anyang, Paris',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _submit,
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          if (_pendingSearch != null) ...[
            const SizedBox(height: 12),
            _CitySearchResults(
              query: _pendingSearch!,
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
                  '풍속 ${weather.windSpeed.toStringAsFixed(1)} m/s',
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
      height: 96,
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
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(day.icon, size: 22),
                const SizedBox(height: 4),
                Text(Formatters.temperature(day.maxTemp), style: theme.textTheme.labelMedium),
                Text(
                  Formatters.temperature(day.minTemp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
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
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: hourlyForecast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final hour = hourlyForecast[index];
          final label = hour.isNow ? '지금' : Formatters.hour24(hour.time);
          return SizedBox(
            width: 44,
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
