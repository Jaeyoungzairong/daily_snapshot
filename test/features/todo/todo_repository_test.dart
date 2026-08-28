import 'package:daily_snapshot/features/todo/data/key_value_store.dart';
import 'package:daily_snapshot/features/todo/data/todo_item.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
}

void main() {
  group('TodoRepository', () {
    test('loadItems returns an empty list when nothing has been saved yet', () async {
      final repository = TodoRepository(store: _InMemoryKeyValueStore());

      expect(await repository.loadItems(), isEmpty);
    });

    test('saveItems then loadItems round-trips the list', () async {
      final repository = TodoRepository(store: _InMemoryKeyValueStore());
      final items = [
        TodoItem(id: '1', text: '할 일 A', done: false, createdAt: DateTime(2026, 8, 28)),
        TodoItem(id: '2', text: '할 일 B', done: true, createdAt: DateTime(2026, 8, 27), completedAt: DateTime(2026, 8, 28)),
      ];

      await repository.saveItems(items);
      final loaded = await repository.loadItems();

      expect(loaded, hasLength(2));
      expect(loaded[0].text, '할 일 A');
      expect(loaded[1].done, isTrue);
      expect(loaded[1].completedAt, DateTime(2026, 8, 28));
    });

    test('loadMemo defaults to an empty string when nothing has been saved yet', () async {
      final repository = TodoRepository(store: _InMemoryKeyValueStore());

      expect(await repository.loadMemo(), '');
    });

    test('saveMemo then loadMemo round-trips the text', () async {
      final repository = TodoRepository(store: _InMemoryKeyValueStore());

      await repository.saveMemo('회의 내용 정리');

      expect(await repository.loadMemo(), '회의 내용 정리');
    });
  });
}
