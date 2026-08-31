import 'package:daily_snapshot/features/todo/data/memo_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoItem json 변환', () {
    test('round-trips title/content/timestamps', () {
      final memo = MemoItem(
        id: '1',
        title: '회의록',
        content: '오늘 논의 내용',
        createdAt: DateTime(2026, 8, 28, 9),
        updatedAt: DateTime(2026, 8, 28, 11, 30),
      );

      final restored = MemoItem.fromJson(memo.toJson());

      expect(restored.id, memo.id);
      expect(restored.title, memo.title);
      expect(restored.content, memo.content);
      expect(restored.createdAt, memo.createdAt);
      expect(restored.updatedAt, memo.updatedAt);
    });

    test('copyWith updates only the given fields', () {
      final memo = MemoItem(
        id: '1',
        title: '제목',
        content: '내용',
        createdAt: DateTime(2026, 8, 28),
        updatedAt: DateTime(2026, 8, 28),
      );

      final renamed = memo.copyWith(title: '새 제목', updatedAt: DateTime(2026, 8, 29));

      expect(renamed.id, memo.id);
      expect(renamed.title, '새 제목');
      expect(renamed.content, memo.content);
      expect(renamed.createdAt, memo.createdAt);
      expect(renamed.updatedAt, DateTime(2026, 8, 29));
    });
  });
}
