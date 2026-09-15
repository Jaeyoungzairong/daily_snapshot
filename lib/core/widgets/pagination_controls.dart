import 'package:flutter/material.dart';

/// 이전/다음 버튼 + "N/M" 페이지 표시. [onPrevious]/[onNext]가 null이면 해당 버튼이
/// 자동으로 비활성화된다(양 끝 페이지에서 호출부가 null을 넘기는 방식).
class PaginationControls extends StatelessWidget {
  const PaginationControls({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  /// 0-indexed 현재 페이지.
  final int page;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: '이전 페이지',
          visualDensity: VisualDensity.compact,
        ),
        Text(
          '${page + 1}/$totalPages',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: '다음 페이지',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
