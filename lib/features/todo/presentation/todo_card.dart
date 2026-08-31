import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/todo_provider.dart';
import '../data/memo_item.dart';
import '../data/todo_item.dart';

/// 삭제 전 실수 방지용 확인 다이얼로그. 사용자가 "삭제"를 눌렀을 때만 true를 반환한다.
Future<bool> _confirmDelete(BuildContext context, {required String title, required String message}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
      ],
    ),
  );
  return confirmed ?? false;
}

class TodoCard extends ConsumerStatefulWidget {
  const TodoCard({super.key});

  @override
  ConsumerState<TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends ConsumerState<TodoCard> {
  final TextEditingController _newItemController = TextEditingController();
  final TextEditingController _memoTitleController = TextEditingController();
  final TextEditingController _memoContentController = TextEditingController();
  Timer? _memoTitleDebounce;
  Timer? _memoContentDebounce;
  bool _memoInitialized = false;
  String? _selectedMemoId;

  @override
  void dispose() {
    _memoTitleDebounce?.cancel();
    _memoContentDebounce?.cancel();
    _newItemController.dispose();
    _memoTitleController.dispose();
    _memoContentController.dispose();
    super.dispose();
  }

  void _addItem() {
    final text = _newItemController.text;
    if (text.trim().isEmpty) return;
    ref.read(todoListProvider.notifier).add(text);
    _newItemController.clear();
  }

  void _selectMemo(String id) {
    _memoTitleDebounce?.cancel();
    _memoContentDebounce?.cancel();
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
    _selectMemo(memo.id);
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
    _memoTitleDebounce?.cancel();
    _memoTitleDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(todoMemoProvider.notifier).renameMemo(id, value);
    });
  }

  void _onMemoContentChanged(String value) {
    final id = _selectedMemoId;
    if (id == null) return;
    _memoContentDebounce?.cancel();
    _memoContentDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(todoMemoProvider.notifier).updateContent(id, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            memosAsync.when(
              loading: () => const LoadingView(),
              error: (error, _) => ErrorView(
                message: error.toString(),
                onRetry: () => ref.invalidate(todoMemoProvider),
              ),
              data: (memos) => _MemoSection(
                memos: memos,
                selectedMemoId: _selectedMemoId,
                titleController: _memoTitleController,
                contentController: _memoContentController,
                onSelect: _selectMemo,
                onAdd: _addMemo,
                onDelete: _deleteSelectedMemo,
                onTitleChanged: _onMemoTitleChanged,
                onContentChanged: _onMemoContentChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoSection extends StatelessWidget {
  const _MemoSection({
    required this.memos,
    required this.selectedMemoId,
    required this.titleController,
    required this.contentController,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onTitleChanged,
    required this.onContentChanged,
  });

  final List<MemoItem> memos;
  final String? selectedMemoId;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onContentChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = selectedMemoId != null && memos.any((memo) => memo.id == selectedMemoId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MemoChipWrap(memos: memos, selectedMemoId: selectedMemoId, onSelect: onSelect, onAdd: onAdd),
        const SizedBox(height: 12),
        if (hasSelection) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  style: theme.textTheme.titleSmall,
                  decoration: const InputDecoration(labelText: '제목', isDense: true),
                  onChanged: onTitleChanged,
                ),
              ),
              IconButton(
                onPressed: () async {
                  final confirmed = await _confirmDelete(
                    context,
                    title: '메모 삭제',
                    message: '이 메모를 삭제할까요? 삭제한 내용은 복구할 수 없습니다.',
                  );
                  if (confirmed) onDelete();
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '메모 삭제',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contentController,
            maxLines: 20,
            onChanged: onContentChanged,
          ),
        ] else
          Text(
            '메모가 없습니다. + 버튼을 눌러 추가해보세요.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
      ],
    );
  }
}

class _MemoChipWrap extends StatelessWidget {
  const _MemoChipWrap({
    required this.memos,
    required this.selectedMemoId,
    required this.onSelect,
    required this.onAdd,
  });

  final List<MemoItem> memos;
  final String? selectedMemoId;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 카드 폭에 맞춰 칩 하나의 최대 너비를 조절한다: 데스크톱 그리드(폭 넓음)에서는
        // 제목이 덜 잘리도록 더 길게, 모바일 컬럼(폭 좁음)에서는 한 줄에 과하게 크지
        // 않도록 줄인다.
        final chipMaxWidth = (constraints.maxWidth / 2).clamp(120.0, 260.0);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final memo in memos)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: chipMaxWidth),
                child: ChoiceChip(
                  label: Text(
                    memo.title.trim().isEmpty ? '(제목 없음)' : memo.title,
                    overflow: TextOverflow.ellipsis,
                  ),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selected: memo.id == selectedMemoId,
                  onSelected: (_) => onSelect(memo.id),
                ),
              ),
            IconButton.filledTonal(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              tooltip: '새 메모 추가',
            ),
          ],
        );
      },
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
              onPressed: () async {
                final confirmed = await _confirmDelete(
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
            style: theme.textTheme.bodyMedium?.copyWith(
              color: item.done ? theme.colorScheme.outline : null,
              decoration: item.done ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        IconButton(
          onPressed: () async {
            final confirmed = await _confirmDelete(
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
