import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_dialog.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/config/local_config.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../exchange_rate/presentation/exchange_rate_card.dart';
import '../../files/application/file_provider.dart';
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

  // 다른 기기에서 "모든 기기에서 로그아웃"을 실행했거나 관리자가 승인을 해제하면, 이 기기가
  // 다음으로 시도하는 Firestore 요청이 permission-denied로 실패한다. 그 상태로 방치하면
  // 카드마다 에러 화면만 보이고 "다시 시도"를 눌러도 세션 자체가 무효라 똑같이 실패한다 —
  // 그래서 감지되는 즉시 이 기기도 로컬 로그아웃시켜 로그인 화면으로 자연스럽게 돌려보낸다.
  // 여러 provider(할일/메모/파일함)가 동시에 같은 이유로 실패할 수 있어 중복 처리를 막는다.
  bool _handlingSessionInvalidation = false;

  void _handlePotentialSessionInvalidation(Object error) {
    if (error is! FirebaseException || error.code != 'permission-denied') return;
    if (_handlingSessionInvalidation) return;
    _handlingSessionInvalidation = true;

    ref.read(authServiceProvider).signOut();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('세션이 만료되어 로그아웃되었습니다. 다시 로그인해주세요.')));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final authState = ref.watch(authUidProvider);
    final email = ref.watch(authEmailProvider).value;

    // 로그인 상태일 때만 구독한다 — 로그아웃 상태에서까지 이 provider들을 듣기 시작하면
    // todoListProvider/todoMemoProvider가 곧바로 "로그인 후에만 사용할 수 있습니다"
    // StateError를 던지며 불필요하게 생성된다(원래는 로그인 후 카드가 직접 watch할 때만
    // 만들어졌다).
    if (authState.value != null) {
      ref.listen(todoListProvider, (previous, next) {
        next.whenOrNull(error: (error, _) => _handlePotentialSessionInvalidation(error));
      });
      ref.listen(todoMemoProvider, (previous, next) {
        next.whenOrNull(error: (error, _) => _handlePotentialSessionInvalidation(error));
      });
      ref.listen(filesProvider, (previous, next) {
        next.whenOrNull(error: (error, _) => _handlePotentialSessionInvalidation(error));
      });
    }
    // 다시 로그인하면(새 세션) 이후에 또 무효화될 수 있으니 다시 감지할 수 있게 풀어둔다.
    ref.listen(authUidProvider, (previous, next) {
      if (next.value != null) _handlingSessionInvalidation = false;
    });

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
