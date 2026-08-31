import 'package:daily_snapshot/core/data/key_value_store.dart';
import 'package:daily_snapshot/features/todo/data/memo_item.dart';
import 'package:daily_snapshot/features/todo/data/todo_item.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);
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

    test('loadMemos returns an empty list when nothing has been saved yet', () async {
      final repository = TodoRepository(store: _InMemoryKeyValueStore());

      expect(await repository.loadMemos(), isEmpty);
    });

    test('saveMemos then loadMemos round-trips the list', () async {
      final repository = TodoRepository(store: _InMemoryKeyValueStore());
      final memos = [
        MemoItem(
          id: '1',
          title: '회의',
          content: '회의 내용 정리',
          createdAt: DateTime(2026, 8, 28),
          updatedAt: DateTime(2026, 8, 28),
        ),
      ];

      await repository.saveMemos(memos);
      final loaded = await repository.loadMemos();

      expect(loaded, hasLength(1));
      expect(loaded.first.title, '회의');
      expect(loaded.first.content, '회의 내용 정리');
    });

    test('loadMemos migrates a legacy single-string memo into one titled item, once', () async {
      final store = _InMemoryKeyValueStore();
      await store.setString('todo_memo', '예전에 적어둔 메모');
      final repository = TodoRepository(store: store);

      final migrated = await repository.loadMemos();

      expect(migrated, hasLength(1));
      expect(migrated.first.title, '메모');
      expect(migrated.first.content, '예전에 적어둔 메모');
      // 옛 키는 이관 후 정리되고, 새 키가 생겼으니 다시 불러도 같은 결과를 유지한다.
      expect(await store.getString('todo_memo'), isNull);
      final reloaded = await repository.loadMemos();
      expect(reloaded, hasLength(1));
      expect(reloaded.first.content, '예전에 적어둔 메모');
    });

    test('loadMemos does not resurrect the legacy memo once the list has been emptied', () async {
      final store = _InMemoryKeyValueStore();
      await store.setString('todo_memo', '예전에 적어둔 메모');
      final repository = TodoRepository(store: store);
      await repository.loadMemos();

      await repository.saveMemos([]);
      final reloaded = await repository.loadMemos();

      expect(reloaded, isEmpty);
    });
  });
}
