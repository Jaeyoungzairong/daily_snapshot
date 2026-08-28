import 'package:daily_snapshot/features/todo/data/todo_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TodoItem json 변환', () {
    test('round-trips a completed item including completedAt', () {
      final item = TodoItem(
        id: '1',
        text: '분기 보고서 초안 작성',
        done: true,
        createdAt: DateTime(2026, 8, 28, 9),
        completedAt: DateTime(2026, 8, 28, 11, 30),
      );

      final restored = TodoItem.fromJson(item.toJson());

      expect(restored.id, item.id);
      expect(restored.text, item.text);
      expect(restored.done, isTrue);
      expect(restored.createdAt, item.createdAt);
      expect(restored.completedAt, item.completedAt);
    });

    test('round-trips a pending item with null completedAt', () {
      final item = TodoItem(
        id: '2',
        text: '3시 팀 미팅',
        done: false,
        createdAt: DateTime(2026, 8, 28, 9),
      );

      final restored = TodoItem.fromJson(item.toJson());

      expect(restored.done, isFalse);
      expect(restored.completedAt, isNull);
    });
  });
}
