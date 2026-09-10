import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../application/todo_provider.dart';
import '../data/todo_item.dart';

class TodoListSection extends ConsumerWidget {
  const TodoListSection({super.key, required this.items});

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

    final hasCompleted = items.any((item) => item.done);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            child: Column(
              children: [
                // 완료 여부와 무관하게 추가한 순서 그대로 보여준다 — 완료했다고 목록
                // 아래로 밀리면 방금 체크한 항목을 눈으로 다시 찾아야 해서 혼란스럽다.
                for (final item in items)
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
              onPressed: () async {
                final confirmed = await confirmAction(
                  context,
                  title: '완료 항목 지우기',
                  message: '완료된 항목을 모두 지울까요?',
                );
                if (confirmed) ref.read(todoListProvider.notifier).clearCompleted();
              },
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
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: item.done ? theme.colorScheme.outline : null,
              decoration: item.done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        IconButton(
          onPressed: () async {
            final confirmed = await confirmAction(
              context,
              title: '할 일 삭제',
              message: '"${item.text}" 항목을 삭제할까요?',
            );
            if (confirmed) onDelete();
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: '삭제',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
