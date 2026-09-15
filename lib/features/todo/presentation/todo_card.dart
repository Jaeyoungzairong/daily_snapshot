import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_reload.dart';
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
    final added = await ref.read(todoListProvider.notifier).add(text);
    if (!mounted) return;
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
        error: (error, _) => ErrorView(message: error.toString(), onRetry: reloadPage),
        data: (uid) => uid == null ? const SignedOutPlaceholder() : _buildSignedInContent(),
      ),
    );
  }

  Widget _buildSignedInContent() {
    final itemsAsync = ref.watch(todoListProvider);

    return itemsAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(message: describeTodoDataError(error), onRetry: reloadPage),
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
