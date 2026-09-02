import 'package:daily_snapshot/features/todo/application/todo_provider.dart';
import 'package:daily_snapshot/features/todo/data/cloud_list_store.dart';
import 'package:daily_snapshot/features/todo/data/todo_item.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryCloudListStore implements CloudListStore {
  final Map<String, List<Map<String, dynamic>>> _docs = {};

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

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      todoRepositoryProvider.overrideWithValue(TodoRepository(store: _InMemoryCloudListStore())),
    ],
  );
  addTearDown(container.dispose);
  // StreamNotifierProvider는 container.read(provider.future)만으로는 스트림을 구독하지
  // 않는다(위젯의 ref.watch처럼 실제로 "듣는" 대상이 있어야 구독이 시작된다) — 그래서 여기서
  // 미리 listen()을 걸어 구독을 켜 둔다. 안 그러면 .future가 영원히 로딩 상태로 멈춘다.
  container.listen(todoListProvider, (_, _) {});
  container.listen(todoMemoProvider, (_, _) {});
  return container;
}

void main() {
  group('todoListProvider', () {
    test('starts empty and add() appends a pending item', () async {
      final container = _makeContainer();

      final initial = await container.read(todoListProvider.future);
      expect(initial, isEmpty);

      await container.read(todoListProvider.notifier).add('3시 팀 미팅');

      final items = container.read(todoListProvider).value!;
      expect(items, hasLength(1));
      expect(items.first.text, '3시 팀 미팅');
      expect(items.first.done, isFalse);
    });

    test('add() ignores blank input', () async {
      final container = _makeContainer();
      await container.read(todoListProvider.future);

      await container.read(todoListProvider.notifier).add('   ');

      expect(container.read(todoListProvider).value, isEmpty);
    });

    test('toggle() marks done and stamps completedAt, toggling back clears it', () async {
      final container = _makeContainer();
      await container.read(todoListProvider.future);
      await container.read(todoListProvider.notifier).add('할 일');
      final id = container.read(todoListProvider).value!.first.id;

      await container.read(todoListProvider.notifier).toggle(id);
      final done = container.read(todoListProvider).value!.first;
      expect(done.done, isTrue);
      expect(done.completedAt, isNotNull);

      await container.read(todoListProvider.notifier).toggle(id);
      final undone = container.read(todoListProvider).value!.first;
      expect(undone.done, isFalse);
      expect(undone.completedAt, isNull);
    });

    test('remove() deletes only the targeted item', () async {
      final container = _makeContainer();
      await container.read(todoListProvider.future);
      final notifier = container.read(todoListProvider.notifier);
      await notifier.add('A');
      await notifier.add('B');
      final idToRemove = container.read(todoListProvider).value!.first.id;

      await notifier.remove(idToRemove);

      final remaining = container.read(todoListProvider).value!;
      expect(remaining, hasLength(1));
      expect(remaining.first.text, 'B');
    });

    test('clearCompleted() removes only done items, keeping pending ones', () async {
      final container = _makeContainer();
      await container.read(todoListProvider.future);
      final notifier = container.read(todoListProvider.notifier);
      await notifier.add('완료할 일');
      await notifier.add('진행중인 일');
      final doneId = container.read(todoListProvider).value!.first.id;
      await notifier.toggle(doneId);

      await notifier.clearCompleted();

      final remaining = container.read(todoListProvider).value!;
      expect(remaining, hasLength(1));
      expect(remaining.first.text, '진행중인 일');
    });

    test('changes persist across a fresh provider read via the same repository', () async {
      final store = _InMemoryCloudListStore();
      final repository = TodoRepository(store: store);

      final container1 = ProviderContainer(
        overrides: [todoRepositoryProvider.overrideWithValue(repository)],
      );
      container1.listen(todoListProvider, (_, _) {});
      await container1.read(todoListProvider.future);
      await container1.read(todoListProvider.notifier).add('저장 확인용');
      container1.dispose();

      final container2 = ProviderContainer(
        overrides: [todoRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container2.dispose);
      container2.listen(todoListProvider, (_, _) {});
      final reloaded = await container2.read(todoListProvider.future);

      expect(reloaded, hasLength(1));
      expect(reloaded.first.text, '저장 확인용');
    });
  });

  group('sortedForDisplay', () {
    test('pending items come before done items, each keeping relative order', () {
      final items = [
        TodoItem(id: '1', text: 'done first', done: true, createdAt: DateTime(2026, 8, 28)),
        TodoItem(id: '2', text: 'pending first', done: false, createdAt: DateTime(2026, 8, 28)),
        TodoItem(id: '3', text: 'done second', done: true, createdAt: DateTime(2026, 8, 28)),
        TodoItem(id: '4', text: 'pending second', done: false, createdAt: DateTime(2026, 8, 28)),
      ];

      final sorted = sortedForDisplay(items);

      expect(sorted.map((e) => e.text), [
        'pending first',
        'pending second',
        'done first',
        'done second',
      ]);
    });
  });

  group('todoMemoProvider', () {
    test('starts empty and addMemo() appends a titled, blank memo', () async {
      final container = _makeContainer();

      final initial = await container.read(todoMemoProvider.future);
      expect(initial, isEmpty);

      final memo = (await container.read(todoMemoProvider.notifier).addMemo())!;

      final memos = container.read(todoMemoProvider).value!;
      expect(memos, hasLength(1));
      expect(memos.first.id, memo.id);
      expect(memos.first.title, '새 메모');
      expect(memos.first.content, '');
    });

    test('renameMemo() and updateContent() only change the targeted memo', () async {
      final container = _makeContainer();
      await container.read(todoMemoProvider.future);
      final notifier = container.read(todoMemoProvider.notifier);
      final first = (await notifier.addMemo())!;
      await notifier.addMemo();

      await notifier.renameMemo(first.id, '회의록');
      await notifier.updateContent(first.id, '오늘 논의 내용');

      final memos = container.read(todoMemoProvider).value!;
      final updated = memos.firstWhere((memo) => memo.id == first.id);
      expect(updated.title, '회의록');
      expect(updated.content, '오늘 논의 내용');
      expect(memos.last.title, '새 메모');
    });

    test('removeMemo() deletes only the targeted memo', () async {
      final container = _makeContainer();
      await container.read(todoMemoProvider.future);
      final notifier = container.read(todoMemoProvider.notifier);
      final first = (await notifier.addMemo())!;
      await notifier.addMemo();

      await notifier.removeMemo(first.id);

      final memos = container.read(todoMemoProvider).value!;
      expect(memos, hasLength(1));
      expect(memos.first.title, '새 메모');
    });
  });
}
