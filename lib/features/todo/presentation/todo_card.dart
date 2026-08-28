import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/todo_provider.dart';
import '../data/todo_item.dart';

class TodoCard extends ConsumerStatefulWidget {
  const TodoCard({super.key});

  @override
  ConsumerState<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends ConsumerState<TodoCard> {
  final TextEditingController _newItemController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  Timer? _memoDebounce;
  bool _memoInitialized = false;

  @override
  void dispose() {
    _memoDebounce?.cancel();
    _newItemController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _newItemController.text;
    if (text.trim().isEmpty) return;
    ref.read(todoListProvider.notifier).add(text);
    _newItemController.clear();
  }

  void _onMemoChanged(String value) {
    _memoDebounce?.cancel();
    _memoDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(todoMemoProvider.notifier).updateMemo(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(todoListProvider);

    // 메모는 비동기로 로드되므로, 처음 값이 도착했을 때 한 번만 컨트롤러에 채운다
    // (그 이후엔 사용자가 입력 중인 텍스트를 덮어쓰면 안 되므로).
    ref.listen(todoMemoProvider, (previous, next) {
      final memo = next.value;
      if (!_memoInitialized && memo != null) {
        _memoInitialized = true;
        _memoController.text = memo;
      }
    });

    return DashboardCard(
      title: '할 일',
      icon: Icons.checklist,
      accentColor: theme.extension<AppAccentColors>()?.todo,
      child: itemsAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error.toString(),
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
                    decoration: const InputDecoration(
                      labelText: '할 일 추가',
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
            _TodoList(items: items),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('메모', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _memoController,
              maxLines: 20,
              // decoration: const InputDecoration(
              //   hintText: '회의 내용, 생각 등 자유롭게 적어보세요',
              // ),
              onChanged: _onMemoChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodoList extends ConsumerWidget {
  const _TodoList({required this.items});

  final List<TodoItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (items.isEmpty) {
      return Text(
        '오늘 할 일을 추가해보세요.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }

    final sorted = sortedForDisplay(items);
    final hasCompleted = sorted.any((item) => item.done);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final item in sorted)
                  _TodoRow(
                    item: item,
                    onToggle: () => ref.read(todoListProvider.notifier).toggle(item.id),
                    onDelete: () => ref.read(todoListProvider.notifier).remove(item.id),
                  ),
              ],
            ),
          ),
        ),
        if (hasCompleted)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => ref.read(todoListProvider.notifier).clearCompleted(),
              child: const Text('완료 항목 지우기'),
            ),
          ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.item, required this.onToggle, required this.onDelete});

  final TodoItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Checkbox(value: item.done, onChanged: (_) => onToggle()),
        Expanded(
          child: Text(
            item.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: item.done ? theme.colorScheme.outline : null,
              decoration: item.done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: '삭제',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
