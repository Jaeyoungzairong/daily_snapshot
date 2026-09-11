import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/todo_provider.dart';
import '../data/memo_item.dart';

class MemoSection extends StatelessWidget {
  const MemoSection({
    super.key,
    required this.memos,
    required this.selectedMemoId,
    required this.titleController,
    required this.contentController,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    required this.onMove,
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
  final ValueChanged<int> onMove;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onContentChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedIndex = memos.indexWhere((memo) => memo.id == selectedMemoId);
    final hasSelection = selectedIndex != -1;

    final captionStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);

    String? timelineLabel;
    if (hasSelection) {
      final createdText = Formatters.dateTime(memos[selectedIndex].createdAt);
      final updatedText = Formatters.dateTime(memos[selectedIndex].updatedAt);
      // 만든 뒤 한 번도 안 고쳤으면 생성 시각 하나만, 고쳤으면 화살표로 이어서 한 줄에.
      timelineLabel = createdText == updatedText
          ? '생성 $createdText'
          : '생성 $createdText → 수정 $updatedText';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MemoChipWrap(
          memos: memos,
          selectedMemoId: selectedMemoId,
          onSelect: onSelect,
          onAdd: onAdd,
        ),
        const SizedBox(height: 16),
        if (hasSelection) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  style: theme.textTheme.titleSmall,
                  maxLength: maxMemoTitleLength,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    isDense: true,
                    counterText: '',
                  ),
                  onChanged: onTitleChanged,
                ),
              ),
              IconButton(
                onPressed: selectedIndex > 0 ? () => onMove(-1) : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: '왼쪽으로 이동',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: selectedIndex < memos.length - 1 ? () => onMove(1) : null,
                icon: const Icon(Icons.chevron_right, size: 18),
                tooltip: '오른쪽으로 이동',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: () async {
                  final confirmed = await confirmAction(
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
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(timelineLabel!, style: captionStyle),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: contentController,
            maxLines: 20,
            maxLength: maxMemoContentLength,
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
    final theme = Theme.of(context);
    final accent = theme.extension<AppAccentColors>()?.todo ?? theme.colorScheme.primary;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
        ? Colors.white
        : Colors.black87;

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
              _MemoChip(
                memo: memo,
                maxWidth: chipMaxWidth,
                selected: memo.id == selectedMemoId,
                accent: accent,
                onAccent: onAccent,
                onSelected: () => onSelect(memo.id),
              ),
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              tooltip: '새 메모 추가',
              style: IconButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.12),
                foregroundColor: accent,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MemoChip extends StatelessWidget {
  const _MemoChip({
    required this.memo,
    required this.maxWidth,
    required this.selected,
    required this.accent,
    required this.onAccent,
    required this.onSelected,
  });

  final MemoItem memo;
  final double maxWidth;
  final bool selected;
  final Color accent;
  final Color onAccent;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = selected ? onAccent : theme.colorScheme.onSurface;
    final isEmpty = memo.content.trim().isEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ChoiceChip(
        avatar: Icon(Icons.sticky_note_2_outlined, size: 16, color: labelColor),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                memo.title.trim().isEmpty ? '(제목 없음)' : memo.title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 아직 내용을 안 쓴 메모라는 걸 눈에 띄게 표시한다.
            if (isEmpty) ...[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: labelColor.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        labelStyle: TextStyle(
          color: labelColor,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selected: selected,
        selectedColor: accent,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: accent.withValues(alpha: selected ? 1 : 0.4)),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
