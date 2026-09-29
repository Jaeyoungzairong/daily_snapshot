import 'dart:async';

import 'package:daily_snapshot/core/auth/auth_provider.dart';
import 'package:daily_snapshot/features/todo/application/todo_provider.dart';
import 'package:daily_snapshot/features/todo/data/cloud_list_store.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firestore의 snapshots()처럼 구독 시 현재 값을 한 번 보내고, 쓰기가 성공할 때마다 새 값을
/// 다시 내보내는 인메모리 저장소. 한 번만 값을 보내는 가짜 저장소로는 "성공한 쓰기의 스냅샷이
/// 뒤늦게 도착해 화면을 바로잡는" 실제 동작을 재현할 수 없어, 롤백 로직을 잘못 검증하게 된다.
class _InMemoryCloudListStore implements CloudListStore {
  final Map<String, List<Map<String, dynamic>>> _docs = {};
  final Map<String, Set<StreamController<List<Map<String, dynamic>>>>> _listeners = {};

  @override
  Stream<List<Map<String, dynamic>>> watch(String docKey) {
    late final StreamController<List<Map<String, dynamic>>> controller;
    controller = StreamController(
      onListen: () {
        controller.add(List.of(_docs[docKey] ?? []));
        _listeners.putIfAbsent(docKey, () => {}).add(controller);
      },
      onCancel: () => _listeners[docKey]?.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<void> mutate(
    String docKey,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) transform,
  ) async {
    _docs[docKey] = transform(_docs[docKey] ?? []);
    for (final controller in _listeners[docKey] ?? const <StreamController<Never>>{}) {
      controller.add(List.of(_docs[docKey]!));
    }
  }
}

/// [failing]이 true인 동안 mutate가 항상 실패하는 저장소(오프라인/권한 거부 상황 재현용).
class _FlakyCloudListStore extends _InMemoryCloudListStore {
  bool failing = false;

  @override
  Future<void> mutate(
    String docKey,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) transform,
  ) async {
    if (failing) {
      await Future<void>.delayed(Duration.zero);
      throw Exception('write failed');
    }
    await super.mutate(docKey, transform);
  }
}

/// 계정 전환 테스트용 로그인 uid.
class _TestUid extends Notifier<String> {
  @override
  String build() => 'uid-a';

  void set(String value) => state = value;
}

ProviderContainer _makeContainer([CloudListStore? store]) {
  final container = ProviderContainer(
    overrides: [
      authUidProvider.overrideWith((ref) => const AsyncData('test-uid')),
      todoRepositoryProvider.overrideWithValue(
        TodoRepository(store: store ?? _InMemoryCloudListStore()),
      ),
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

    test('add() rolls back to the previous state and rethrows when the write fails', () async {
      final store = _FlakyCloudListStore();
      final container = _makeContainer(store);
      await container.read(todoListProvider.future);
      final notifier = container.read(todoListProvider.notifier);
      await notifier.add('저장된 항목');

      store.failing = true;
      await expectLater(() => notifier.add('실패할 항목'), throwsException);

      final items = container.read(todoListProvider).value!;
      expect(items, hasLength(1));
      expect(items.first.text, '저장된 항목');
    });

    test('toggle() rolls back only the failed change, keeping earlier successful ones', () async {
      final store = _FlakyCloudListStore();
      final container = _makeContainer(store);
      await container.read(todoListProvider.future);
      final notifier = container.read(todoListProvider.notifier);
      await notifier.add('A');
      await notifier.add('B');
      final idA = container.read(todoListProvider).value!.first.id;

      store.failing = true;
      await expectLater(() => notifier.toggle(idA), throwsException);

      final items = container.read(todoListProvider).value!;
      expect(items, hasLength(2));
      expect(items.first.done, isFalse);
    });

    test('two overlapping writes that both fail leave the server state on screen', () async {
      final store = _FlakyCloudListStore();
      final container = _makeContainer(store);
      await container.read(todoListProvider.future);
      final notifier = container.read(todoListProvider.notifier);
      await notifier.add('A');
      await notifier.add('B');
      await pumpEventQueue();
      final ids = container.read(todoListProvider).value!.map((i) => i.id).toList();

      // 오프라인에서 체크박스 두 개를 연달아 누른 상황 — 첫 쓰기가 끝나기 전에 두 번째가 시작된다.
      store.failing = true;
      final first = notifier.toggle(ids[0]);
      final second = notifier.toggle(ids[1]);
      await expectLater(first, throwsException);
      await expectLater(second, throwsException);

      final items = container.read(todoListProvider).value!;
      expect(items.map((i) => i.done), [false, false]);
    });

    test('a failure after another write succeeded keeps the succeeded change', () async {
      final store = _FlakyCloudListStore();
      final container = _makeContainer(store);
      await container.read(todoListProvider.future);
      final notifier = container.read(todoListProvider.notifier);
      await notifier.add('A');
      await notifier.add('B');
      final ids = container.read(todoListProvider).value!.map((i) => i.id).toList();

      await notifier.toggle(ids[1]);
      await pumpEventQueue();
      store.failing = true;
      await expectLater(notifier.toggle(ids[0]), throwsException);

      final items = container.read(todoListProvider).value!;
      expect(items.map((i) => i.done), [false, true]);
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

    test(
      'scheduleRename()/scheduleContent() save automatically after the debounce delay',
      () async {
        final container = _makeContainer();
        await container.read(todoMemoProvider.future);
        final notifier = container.read(todoMemoProvider.notifier);
        final memo = (await notifier.addMemo())!;

        notifier.scheduleRename(memo.id, '디바운스 제목');
        notifier.scheduleContent(memo.id, '디바운스 내용');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        final updated = container.read(todoMemoProvider).value!.first;
        expect(updated.title, '디바운스 제목');
        expect(updated.content, '디바운스 내용');
      },
    );

    test(
      'flushPending() saves a scheduled edit immediately without waiting for the debounce',
      () async {
        final container = _makeContainer();
        await container.read(todoMemoProvider.future);
        final notifier = container.read(todoMemoProvider.notifier);
        final memo = (await notifier.addMemo())!;

        notifier.scheduleRename(memo.id, '즉시 저장 제목');
        await notifier.flushPending();

        final updated = container.read(todoMemoProvider).value!.first;
        expect(updated.title, '즉시 저장 제목');
      },
    );

    test('cancelPendingEdits() discards a scheduled edit instead of saving it', () async {
      final container = _makeContainer();
      await container.read(todoMemoProvider.future);
      final notifier = container.read(todoMemoProvider.notifier);
      final memo = (await notifier.addMemo())!;

      notifier.scheduleContent(memo.id, '버려질 내용');
      notifier.cancelPendingEdits();
      await Future<void>.delayed(const Duration(milliseconds: 700));

      final updated = container.read(todoMemoProvider).value!.first;
      expect(updated.content, '');
    });

    test('addMemo() rolls back to the previous state and rethrows when the write fails', () async {
      final store = _FlakyCloudListStore();
      final container = _makeContainer(store);
      await container.read(todoMemoProvider.future);
      final notifier = container.read(todoMemoProvider.notifier);
      await notifier.addMemo();

      store.failing = true;
      await expectLater(() => notifier.addMemo(), throwsException);

      final memos = container.read(todoMemoProvider).value!;
      expect(memos, hasLength(1));
    });

    test(
      'a failed debounced save reports memoSaveFailureProvider once, and flushPending retries it',
      () async {
        final store = _FlakyCloudListStore();
        final container = _makeContainer(store);
        await container.read(todoMemoProvider.future);
        final notifier = container.read(todoMemoProvider.notifier);
        final memo = (await notifier.addMemo())!;

        expect(container.read(memoSaveFailureProvider), 0);

        store.failing = true;
        notifier.scheduleRename(memo.id, '실패할 제목');
        await Future<void>.delayed(const Duration(milliseconds: 700));

        // renameMemo는 debounce 경로에서 직접 상태를 바꾸므로(입력 중인 텍스트필드 값이
        // 그대로 남아야 함), 저장 실패해도 화면 값은 되돌리지 않는다 — 대신 대기 값
        // (_pendingTitleId/_pendingTitleValue)이 지워지지 않아 flushPending이 재시도할 수
        // 있고, 실패 알림은 한 번만 센다.
        expect(container.read(memoSaveFailureProvider), 1);
        expect(container.read(todoMemoProvider).value!.first.title, '실패할 제목');
        // 스낵바와 달리 저장될 때까지 계속 남는 "저장 안 된 편집" 상태.
        expect(container.read(memoUnsavedEditsProvider), isTrue);
        expect(notifier.hasUnsavedEdits, isTrue);

        // 여전히 실패하는 동안 재시도해도 상태는 유지된다(로그아웃 전 확인이 이 값을 본다).
        await notifier.flushPending();
        expect(notifier.hasUnsavedEdits, isTrue);
        expect(container.read(memoSaveFailureProvider), 1);

        store.failing = false;
        await notifier.flushPending();
        expect(container.read(memoUnsavedEditsProvider), isFalse);
        expect(notifier.hasUnsavedEdits, isFalse);
        // 저장이 다시 성공했으니 실패 카운트는 더 늘지 않는다.
        final failureCountAfterRetry = container.read(memoSaveFailureProvider);
        container.dispose();
        expect(failureCountAfterRetry, 1);

        // 화면 상태만으로는 실제로 서버에 쓰였는지 알 수 없으니(디바운스 경로는 실패해도
        // 낙관적 표시를 유지하므로), 같은 저장소를 새 컨테이너로 다시 읽어 flushPending이
        // 실제로 저장을 재시도했는지 확인한다.
        final freshContainer = ProviderContainer(
          overrides: [
            authUidProvider.overrideWith((ref) => const AsyncData('test-uid')),
            todoRepositoryProvider.overrideWithValue(TodoRepository(store: store)),
          ],
        );
        addTearDown(freshContainer.dispose);
        freshContainer.listen(todoMemoProvider, (_, _) {});
        final reloaded = await freshContainer.read(todoMemoProvider.future);
        expect(reloaded.first.title, '실패할 제목');
      },
    );
  });

  // Riverpod은 provider를 다시 빌드할 때 Notifier 인스턴스를 재사용하고 build()만 다시
  // 부른다 — 예전엔 _repository가 late final이라 두 번째 build()에서 LateInitializationError가
  // 나 할일/메모 카드가 앱을 다시 시작할 때까지 복구되지 않았다.
  group('rebuilding the notifiers', () {
    test('invalidate ("다시 시도") rebuilds todo/memo without error', () async {
      final container = _makeContainer();
      await container.read(todoListProvider.future);
      await container.read(todoMemoProvider.future);
      await container.read(todoListProvider.notifier).add('할 일');

      container.invalidate(todoListProvider);
      container.invalidate(todoMemoProvider);
      final items = await container.read(todoListProvider.future);
      await container.read(todoMemoProvider.future);

      expect(container.read(todoListProvider).hasError, isFalse);
      expect(container.read(todoMemoProvider).hasError, isFalse);
      expect(items.single.text, '할 일');
      // 다시 빌드된 뒤에도 쓰기가 정상 동작해야 한다.
      await container.read(todoListProvider.notifier).add('두 번째');
      expect(container.read(todoListProvider).value, hasLength(2));
    });

    test('switching accounts rebuilds against the new account\'s repository', () async {
      final stores = {'uid-a': _InMemoryCloudListStore(), 'uid-b': _InMemoryCloudListStore()};
      final uid = NotifierProvider<_TestUid, String>(_TestUid.new);
      final container = ProviderContainer(
        overrides: [
          authUidProvider.overrideWith((ref) => AsyncData(ref.watch(uid))),
          todoRepositoryProvider.overrideWith(
            (ref) => TodoRepository(store: stores[ref.watch(uid)]!),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(todoListProvider, (_, _) {});
      container.listen(todoMemoProvider, (_, _) {});

      await container.read(todoListProvider.future);
      await container.read(todoMemoProvider.future);
      await container.read(todoListProvider.notifier).add('A의 할 일');

      container.read(uid.notifier).set('uid-b');
      final itemsB = await container.read(todoListProvider.future);
      await container.read(todoMemoProvider.future);

      expect(container.read(todoListProvider).hasError, isFalse);
      expect(container.read(todoMemoProvider).hasError, isFalse);
      expect(itemsB, isEmpty);
      // 새 계정에서의 쓰기는 새 계정 저장소에만 들어가야 한다.
      await container.read(todoListProvider.notifier).add('B의 할 일');
      expect(container.read(todoListProvider).value!.single.text, 'B의 할 일');
    });
  });
}
