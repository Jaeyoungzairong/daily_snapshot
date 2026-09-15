import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../application/todo_provider.dart';
import '../data/todo_item.dart';

class TodoListSection extends ConsumerStatefulWidget {
  const TodoListSection({super.key, required this.items});

  final List<TodoItem> items;

  @override
  ConsumerState<TodoListSection> createState() => _TodoListSectionState();
}

class _TodoListSectionState extends ConsumerState<TodoListSection> {
  // 특정 상한을 전제하지 않고 항목 개수에 따라 페이지 수를 그때그때 계산하므로
  // 상한(maxTodoItems)이 바뀌어도 그대로 동작한다.
  static const int _pageSize = 15;

  // 항목이 삭제돼 페이지 수가 줄어들 수 있어, 이 필드를 직접 쓰지 않고 build 안에서
  // 항상 clamp한 값(page)만 슬라이싱/버튼 상태/다음 값 계산에 공통으로 사용한다.
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items;

    if (items.isEmpty) {
      return Text(
        '오늘 할 일을 추가해보세요.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      );
    }

    final hasCompleted = items.any((item) => item.done);
    final totalPages = (items.length / _pageSize).ceil();
    final page = _currentPage.clamp(0, totalPages - 1);
    final pageItems = items.skip(page * _pageSize).take(_pageSize);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 할 일 텍스트가 길면 두 줄까지 wrap될 수 있어(_TodoRow의 maxLines: 2) 한
        // 페이지(최대 _pageSize개)의 높이가 완전히 고정되진 않는다 — 안전장치로
        // 스크롤을 유지한다.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 720),
          child: SingleChildScrollView(
            child: Column(
              children: [
                // 완료 여부와 무관하게 추가한 순서 그대로 보여준다 — 완료했다고 목록
                // 아래로 밀리면 방금 체크한 항목을 눈으로 다시 찾아야 해서 혼란스럽다.
                for (final item in pageItems)
                  _TodoRow(
                    key: ValueKey(item.id),
                    item: item,
                    onToggle: () => ref.read(todoListProvider.notifier).toggle(item.id),
                    onDelete: () => ref.read(todoListProvider.notifier).remove(item.id),
                  ),
              ],
            ),
          ),
        ),
        if (totalPages > 1) ...[
          const SizedBox(height: 4),
          PaginationControls(
            page: page,
            totalPages: totalPages,
            onPrevious: page > 0 ? () => setState(() => _currentPage = page - 1) : null,
            onNext: page < totalPages - 1 ? () => setState(() => _currentPage = page + 1) : null,
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${items.length}/$maxTodoItems개',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            if (hasCompleted)
              TextButton(
                onPressed: () async {
                  final confirmed = await confirmAction(
                    context,
                    title: '완료 항목 지우기',
                    message: '완료된 항목을 모두 지울까요?',
                  );
                  if (confirmed) ref.read(todoListProvider.notifier).clearCompleted();
                },
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                child: const Text('완료 항목 지우기'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({super.key, required this.item, required this.onToggle, required this.onDelete});

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
