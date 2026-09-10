import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_dialog.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/config/local_config.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../exchange_rate/presentation/exchange_rate_card.dart';
import '../../files/presentation/file_card.dart';
import '../../shortcuts/presentation/shortcuts_card.dart';
import '../../todo/application/todo_provider.dart';
import '../../todo/presentation/todo_card.dart';
import '../../weather/presentation/weather_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  static const double _wideBreakpoint = 900;
  static const List<Widget> _cards = [
    WeatherCard(),
    ShortcutsCard(),
    TodoCard(),
    FileCard(),
    ExchangeRateCard(),
  ];

  @override
  void initState() {
    super.initState();
    // 이메일 로그인 링크를 눌러 들어온 경우, 계정 아이콘을 직접 찾지 않아도 바로
    // 로그인 확인 화면을 보여준다. 이 앱은 화면 전환이 없는 단일 페이지라
    // initState는 앱 로드당 한 번만 실행된다.
    if (ref.read(authServiceProvider).isSignInLink(Uri.base.toString())) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showAccountDialog(context);
      });
    }
  }

  void _showAccountDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AccountDialog(
        // 로그아웃 직전, 아직 저장 안 된 메모 편집 내용을 flush한다. 대시보드가 이미
        // TodoCard를 구성하는 조합 루트라 이 의존은 자연스럽고, core/auth 쪽으로는
        // todo 전용 provider가 새어 들어가지 않는다.
        onBeforeSignOut: () => ref.read(todoMemoProvider.notifier).flushPending(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final authState = ref.watch(authUidProvider);
    final email = ref.watch(authEmailProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/images/app_icon.png', width: 28, height: 28),
            ),
            const SizedBox(width: 10),
            const Text('데일리 스냅샷'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: authState.value == null ? '로그인' : (email ?? '계정'),
            icon: Icon(
              authState.value == null ? Icons.account_circle_outlined : Icons.account_circle,
            ),
            onPressed: () => _showAccountDialog(context),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: isDark ? '라이트 테마로 전환' : '다크 테마로 전환',
            icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: isWide ? _buildGrid() : _buildColumn(),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'v${LocalConfig.appVersion}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
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
      children: _cards.map((card) => SizedBox(width: 560, child: card)).toList(),
    );
  }

  Widget _buildColumn() {
    return Column(
      children: [
        for (final card in _cards) ...[card, const SizedBox(height: 16)],
      ],
    );
  }
}
