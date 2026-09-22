import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../../../core/widgets/signed_out_placeholder.dart';
import '../application/todo_provider.dart';
import 'todo_error.dart';
import 'todo_list_section.dart';

class TodoCard extends ConsumerStatefulWidget {
  const TodoCard({super.key});

  @override
  ConsumerState<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends ConsumerState<TodoCard> {
  final TextEditingController _newItemController = TextEditingController();

  @override
  void dispose() {
    _newItemController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    final text = _newItemController.text;
    if (text.trim().isEmpty) return;
    var added = false;
    final saved = await runTodoWrite(context, () async {
      added = await ref.read(todoListProvider.notifier).add(text);
    });
    // 저장에 실패하면 runTodoWrite가 이미 안내했고, 입력창도 비우지 않아 다시 시도할 수 있다.
    if (!saved || !mounted) return;
    if (added) {
      _newItemController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('할 일은 최대 $maxTodoItems개까지 추가할 수 있습니다. 완료된 항목을 정리해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authUidProvider);

    // 로그아웃(uid가 null이 됨)하면 이전 세션의 입력 상태가 다음 로그인 때
    // 잘못 남아있지 않도록 초기화한다.
    ref.listen(authUidProvider, (previous, next) {
      if (next.value == null) {
        _newItemController.clear();
      }
    });

    return DashboardCard(
      title: '할 일',
      icon: Icons.checklist,
      accentColor: theme.extension<AppAccentColors>()?.todo,
      child: authState.when(
        loading: () => const LoadingView(),
        // 예전엔 웹의 페이지 새로고침(reloadPage)에 기댔는데, 안드로이드는 이 함수가
        // 빈 구현이라 버튼을 눌러도 아무 반응이 없었다 — authServiceProvider를
        // invalidate하면 인증 스트림 구독 자체를 다시 만들어서 두 플랫폼 모두에서 동작한다.
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(authServiceProvider),
        ),
        data: (uid) => uid == null ? const SignedOutPlaceholder() : _buildSignedInContent(),
      ),
    );
  }

  Widget _buildSignedInContent() {
    final itemsAsync = ref.watch(todoListProvider);

    return itemsAsync.when(
      loading: () => const LoadingView(),
      // 같은 이유로 todoListProvider만 다시 구독하도록 invalidate한다 — 전체 페이지를
      // 새로고침하지 않아도 되고 안드로이드에서도 동일하게 동작한다.
      error: (error, _) => ErrorView(
        message: describeTodoDataError(error),
        onRetry: () => ref.invalidate(todoListProvider),
      ),
      data: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newItemController,
                  maxLength: maxTodoTextLength,
                  decoration: const InputDecoration(
                    labelText: '할 일 추가',
                    counterText: '',
                    //hintText: '예: 3시 팀 미팅 자료 준비',
                  ),
                  onSubmitted: (_) => _addItem(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                tooltip: '할 일 추가',
              ),
            ],
          ),
          const SizedBox(height: 12),
          TodoListSection(items: items),
        ],
      ),
    );
  }
}
