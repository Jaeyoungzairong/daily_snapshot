import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/account_dialog.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/config/app_version_provider.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../exchange_rate/presentation/exchange_rate_card.dart';
import '../../files/application/file_provider.dart';
import '../../files/presentation/file_card.dart';
import '../../shortcuts/presentation/shortcuts_card.dart';
import '../../todo/application/todo_provider.dart';
import '../../todo/presentation/memo_card.dart';
import '../../todo/presentation/todo_card.dart';
import '../../weather/presentation/weather_card.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  static const double _wideBreakpoint = 900;

  // 넓은 화면(Wrap)과 좁은 화면(Column)은 부모 위젯 타입 자체가 달라서, 폭이 경계값을
  // 넘나들 때 GlobalKey 없이는 Flutter가 각 카드를 언마운트했다가 새로 마운트한다 —
  // 그러면 카드마다 갖고 있던 로컬 상태(예: 메모 카드의 선택된 메모, 파일함/할일의 현재
  // 페이지)가 리사이즈 한 번에 전부 날아간다. GlobalKey를 주면 Flutter가 부모가 바뀌어도
  // 같은 엘리먼트를 찾아 그대로 옮겨 상태를 보존한다.
  final _weatherKey = GlobalKey();
  final _shortcutsKey = GlobalKey();
  final _memoKey = GlobalKey();
  final _todoKey = GlobalKey();
  final _fileKey = GlobalKey();
  final _exchangeRateKey = GlobalKey();

  // 안드로이드는 할일/메모/공유파일함만 지원한다 — 날씨/환율/바로가기는 웹 전용 기능
  // (위치 조회, 외부 탭 열기 등)에 기대고 있어 범위에서 제외했다. 원래(웹 전용 시절) 순서인
  // 날씨·바로가기·메모·할일·파일함·환율을 그대로 유지하고, 안드로이드에서 제외되는 카드만
  // 조건부로 뺀다.
  late final List<Widget> _cards = [
    if (kIsWeb) ...[WeatherCard(key: _weatherKey), ShortcutsCard(key: _shortcutsKey)],
    MemoCard(key: _memoKey),
    TodoCard(key: _todoKey),
    FileCard(key: _fileKey),
    if (kIsWeb) ExchangeRateCard(key: _exchangeRateKey),
  ];

  @override
  void initState() {
    super.initState();
    // 이메일 로그인 링크를 눌러 들어온 경우, 계정 아이콘을 직접 찾지 않아도 바로 로그인
    // 확인 화면을 보여준다(웹 전용 — 안드로이드는 이메일 링크를 받지 않고 Google 로그인만
    // 쓴다). 이 앱은 화면 전환이 없는 단일 페이지라 initState는 앱 로드당 한 번만 실행된다.
    if (kIsWeb && ref.read(authServiceProvider).isSignInLink(Uri.base.toString())) {
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
  // 여러 provider(할일/메모/파일함/isSessionValidProvider)가 동시에 같은 이유로 실패할 수
  // 있어 sessionInvalidationHandledProvider로 중복 처리를 막는다 — 이 가드는 "다른 모든
  // 기기에서 로그아웃" 버튼을 누른 기기 자신도 선점하므로 그쪽과 공유한다.
  void _handlePotentialSessionInvalidation(Object error) {
    if (error is! FirebaseException || error.code != 'permission-denied') return;
    _signOutForInvalidSession();
  }

  void _signOutForInvalidSession() {
    if (ref.read(sessionInvalidationHandledProvider)) return;
    ref.read(sessionInvalidationHandledProvider.notifier).set(true);

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
    final appVersion = ref.watch(appVersionProvider).value;

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
      // Firestore/Storage 규칙이 실제로 거부할 때까지 기다리면(재시도 백오프 때문에)
      // 체감상 느려서, admin_allowed_emails 문서를 직접 구독해 더 빠르게 반응한다.
      ref.listen(isSessionValidProvider, (previous, next) {
        if (next == false) _signOutForInvalidSession();
      });
    }
    // 다시 로그인하면(새 세션) 이후에 또 무효화될 수 있으니 다시 감지할 수 있게 풀어둔다.
    ref.listen(authUidProvider, (previous, next) {
      if (next.value != null) ref.read(sessionInvalidationHandledProvider.notifier).set(false);
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
                    appVersion == null ? '' : 'v$appVersion',
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
