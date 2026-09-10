import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_reload.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../../../core/widgets/signed_out_placeholder.dart';
import '../application/todo_provider.dart';
import 'memo_section.dart';
import 'todo_list_section.dart';

class TodoCard extends ConsumerStatefulWidget {
  const TodoCard({super.key});

  @override
  ConsumerState<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends ConsumerState<TodoCard> {
  final TextEditingController _newItemController = TextEditingController();
  final TextEditingController _memoTitleController = TextEditingController();
  final TextEditingController _memoContentController = TextEditingController();
  bool _memoInitialized = false;
  String? _selectedMemoId;

  @override
  void dispose() {
    _newItemController.dispose();
    _memoTitleController.dispose();
    _memoContentController.dispose();
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

  void _selectMemo(String id) {
    ref.read(todoMemoProvider.notifier).cancelPendingEdits();
    final memos = ref.read(todoMemoProvider).value ?? [];
    final index = memos.indexWhere((memo) => memo.id == id);
    if (index == -1) return;
    final memo = memos[index];
    setState(() {
      _selectedMemoId = memo.id;
      _memoTitleController.text = memo.title;
      _memoContentController.text = memo.content;
    });
  }

  Future<void> _addMemo() async {
    final memo = await ref.read(todoMemoProvider.notifier).addMemo();
    if (!mounted) return;
    if (memo != null) {
      _selectMemo(memo.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메모는 최대 $maxMemoCount개까지 만들 수 있습니다.')),
      );
    }
  }

  Future<void> _moveSelectedMemo(int delta) async {
    final id = _selectedMemoId;
    if (id == null) return;
    await ref.read(todoMemoProvider.notifier).moveMemo(id, delta);
  }

  Future<void> _deleteSelectedMemo() async {
    final id = _selectedMemoId;
    if (id == null) return;
    await ref.read(todoMemoProvider.notifier).removeMemo(id);
    final remaining = ref.read(todoMemoProvider).value ?? [];
    if (remaining.isEmpty) {
      setState(() {
        _selectedMemoId = null;
        _memoTitleController.clear();
        _memoContentController.clear();
      });
    } else {
      _selectMemo(remaining.first.id);
    }
  }

  void _onMemoTitleChanged(String value) {
    final id = _selectedMemoId;
    if (id == null) return;
    ref.read(todoMemoProvider.notifier).scheduleRename(id, value);
  }

  void _onMemoContentChanged(String value) {
    final id = _selectedMemoId;
    if (id == null) return;
    ref.read(todoMemoProvider.notifier).scheduleContent(id, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authUidProvider);

    // 로그아웃(uid가 null이 됨)하면 이전 세션의 메모 선택 상태가 다음 로그인 때
    // 잘못 남아있지 않도록 초기화한다.
    ref.listen(authUidProvider, (previous, next) {
      if (next.value == null) {
        _selectedMemoId = null;
        _memoInitialized = false;
        _newItemController.clear();
        _memoTitleController.clear();
        _memoContentController.clear();
      }
    });

    return DashboardCard(
      title: '할 일·메모',
      icon: Icons.checklist,
      accentColor: theme.extension<AppAccentColors>()?.todo,
      child: authState.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error.toString(), onRetry: reloadPage),
        data: (uid) => uid == null ? const SignedOutPlaceholder() : _buildSignedInContent(theme),
      ),
    );
  }

  Widget _buildSignedInContent(ThemeData theme) {
    final itemsAsync = ref.watch(todoListProvider);
    final memosAsync = ref.watch(todoMemoProvider);

    // 메모 목록은 비동기로 로드되므로, 처음 도착했을 때 한 번만 첫 메모를 선택해 채운다
    // (그 이후엔 사용자가 선택/입력 중인 내용을 덮어쓰면 안 되므로).
    ref.listen(todoMemoProvider, (previous, next) {
      final memos = next.value;
      if (!_memoInitialized && memos != null) {
        _memoInitialized = true;
        if (memos.isNotEmpty) {
          _selectedMemoId = memos.first.id;
          _memoTitleController.text = memos.first.title;
          _memoContentController.text = memos.first.content;
        }
      }
    });

    return itemsAsync.when(
      loading: () => const LoadingView(),
      error: (error, _) => ErrorView(
        message: _describeDataError(error),
        onRetry: reloadPage,
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
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text('메모', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          memosAsync.when(
            loading: () => const LoadingView(),
            error: (error, _) => ErrorView(
              message: _describeDataError(error),
              onRetry: reloadPage,
            ),
            data: (memos) => MemoSection(
              memos: memos,
              selectedMemoId: _selectedMemoId,
              titleController: _memoTitleController,
              contentController: _memoContentController,
              onSelect: _selectMemo,
              onAdd: _addMemo,
              onDelete: _deleteSelectedMemo,
              onMove: _moveSelectedMemo,
              onTitleChanged: _onMemoTitleChanged,
              onContentChanged: _onMemoContentChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 할일/메모 Firestore 스트림에서 발생한 에러를 사용자에게 보여줄 한국어 메시지로 바꾼다.
String _describeDataError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '승인이 해제되었습니다. 관리자에게 문의해주세요.';
      case 'unavailable':
        return '네트워크 연결을 확인해주세요.';
    }
  }
  return '일시적인 오류가 발생했습니다. 다시 시도해주세요.';
}
