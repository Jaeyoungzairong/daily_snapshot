import 'package:daily_snapshot/features/todo/data/cloud_list_store.dart';
import 'package:daily_snapshot/features/todo/data/memo_item.dart';
import 'package:daily_snapshot/features/todo/data/todo_item.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryCloudListStore implements CloudListStore {
  final Map<String, List<Map<String, dynamic>>> _docs = {};

  /// 손상된 항목이 섞인 문서를 재현하기 위해 원시 데이터를 그대로 심는다.
  void seed(String docKey, List<Map<String, dynamic>> entries) => _docs[docKey] = entries;

  List<Map<String, dynamic>> raw(String docKey) => _docs[docKey] ?? [];

  @override
  Stream<List<Map<String, dynamic>>> watch(String docKey) async* {
    yield _docs[docKey] ?? [];
  }

  @override
  Future<void> mutate(
    String docKey,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) transform,
  ) async {
    _docs[docKey] = transform(_docs[docKey] ?? []);
  }
}

void main() {
  group('TodoRepository · items', () {
    test('watchItems starts empty and reflects addItem/toggleItem/removeItem', () async {
      final repository = TodoRepository(store: _InMemoryCloudListStore());

      expect(await repository.watchItems().first, isEmpty);

      final item = TodoItem(id: '1', text: '할 일 A', done: false, createdAt: DateTime(2026, 8, 28));
      await repository.addItem(item);
      expect((await repository.watchItems().first).single.text, '할 일 A');

      await repository.toggleItem('1');
      final toggled = (await repository.watchItems().first).single;
      expect(toggled.done, isTrue);
      expect(toggled.completedAt, isNotNull);

      await repository.removeItem('1');
      expect(await repository.watchItems().first, isEmpty);
    });

    test('clearCompletedItems keeps only pending items', () async {
      final repository = TodoRepository(store: _InMemoryCloudListStore());
      await repository.addItem(
        TodoItem(id: '1', text: 'A', done: true, createdAt: DateTime(2026, 8, 28)),
      );
      await repository.addItem(
        TodoItem(id: '2', text: 'B', done: false, createdAt: DateTime(2026, 8, 28)),
      );

      await repository.clearCompletedItems();

      final remaining = await repository.watchItems().first;
      expect(remaining, hasLength(1));
      expect(remaining.first.text, 'B');
    });
  });

  group('TodoRepository · corrupted entries', () {
    final goodJson = TodoItem(
      id: 'ok',
      text: '정상 항목',
      done: false,
      createdAt: DateTime(2026, 8, 28),
    ).toJson();
    // done이 문자열, createdAt 누락 — Firebase 콘솔에서 잘못 편집한 상황.
    final brokenJson = <String, dynamic>{'id': 'bad', 'text': '손상 항목', 'done': 'yes'};

    test('watchItems skips unreadable entries instead of failing the whole stream', () async {
      final store = _InMemoryCloudListStore()..seed('todo_items', [goodJson, brokenJson]);
      final repository = TodoRepository(store: store);

      final items = await repository.watchItems().first;

      expect(items.map((i) => i.id), ['ok']);
    });

    test('mutations keep unreadable entries in the document instead of deleting them', () async {
      final store = _InMemoryCloudListStore()..seed('todo_items', [goodJson, brokenJson]);
      final repository = TodoRepository(store: store);

      await repository.toggleItem('ok');

      final raw = store.raw('todo_items');
      expect(raw, hasLength(2));
      expect(raw.first['done'], isTrue);
      expect(raw.last, brokenJson);
    });

    test('watchMemos skips unreadable memos too', () async {
      final now = DateTime(2026, 8, 28);
      final goodMemo = MemoItem(
        id: 'm1',
        title: '정상',
        content: '',
        createdAt: now,
        updatedAt: now,
      ).toJson();
      final store = _InMemoryCloudListStore()
        ..seed('todo_memos', [
          <String, dynamic>{'id': 'broken'},
          goodMemo,
        ]);
      final repository = TodoRepository(store: store);

      final memos = await repository.watchMemos().first;

      expect(memos.map((m) => m.id), ['m1']);
    });
  });

  group('TodoRepository · memos', () {
    test('watchMemos reflects addMemo/renameMemo/updateMemoContent/removeMemo/moveMemo', () async {
      final repository = TodoRepository(store: _InMemoryCloudListStore());
      final now = DateTime(2026, 8, 28);
      final memoA = MemoItem(id: 'a', title: '메모 A', content: '', createdAt: now, updatedAt: now);
      final memoB = MemoItem(id: 'b', title: '메모 B', content: '', createdAt: now, updatedAt: now);

      await repository.addMemo(memoA);
      await repository.addMemo(memoB);
      expect((await repository.watchMemos().first).map((m) => m.id), ['a', 'b']);

      await repository.moveMemo('b', -1);
      expect((await repository.watchMemos().first).map((m) => m.id), ['b', 'a']);

      await repository.renameMemo('a', '회의록');
      await repository.updateMemoContent('a', '오늘 논의 내용');
      final updated = (await repository.watchMemos().first).firstWhere((m) => m.id == 'a');
      expect(updated.title, '회의록');
      expect(updated.content, '오늘 논의 내용');

      await repository.removeMemo('b');
      expect((await repository.watchMemos().first).map((m) => m.id), ['a']);
    });
  });
}
