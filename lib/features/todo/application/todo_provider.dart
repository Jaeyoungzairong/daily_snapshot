import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/cloud_list_store.dart';
import '../data/memo_item.dart';
import '../data/todo_item.dart';
import '../data/todo_repository.dart';

/// 로그인(uid)이 있을 때만 만들어진다 — TodoCard가 로그인 안 됐을 때는 이 provider를
/// 아예 보지 않으므로, 여기서 uid가 없어 던지는 예외는 실제로는 발생하지 않는 방어 코드다.
final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  final uid = ref.watch(authUidProvider).value;
  if (uid == null) {
    throw StateError('로그인 후에만 사용할 수 있습니다.');
  }
  return TodoRepository(store: FirestoreListStore(uid: uid));
});

class TodoListNotifier extends StreamNotifier<List<TodoItem>> {
  late final TodoRepository _repository;

  // 타임스탬프만으로는 같은 마이크로초에 연달아 추가될 경우 id가 겹칠 수 있어
  // (예: 테스트에서 add()를 연속 호출) 인스턴스 수명 동안 증가만 하는 카운터를 더한다.
  int _idSequence = 0;

  @override
  Stream<List<TodoItem>> build() {
    _repository = ref.watch(todoRepositoryProvider);
    return _repository.watchItems();
  }

  Future<void> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final current = state.value ?? [];
    final item = TodoItem(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}',
      text: trimmed,
      done: false,
      createdAt: DateTime.now(),
    );
    // 낙관적으로 먼저 반영 — 실제 확정 값은 뒤이어 Firestore 실시간 스트림으로 들어온다.
    state = AsyncData([...current, item]);
    await _repository.addItem(item);
  }

  Future<void> toggle(String id) async {
    final current = state.value ?? [];
    state = AsyncData([
      for (final item in current)
        if (item.id == id)
          item.copyWith(done: !item.done, completedAt: item.done ? null : DateTime.now())
        else
          item,
    ]);
    await _repository.toggleItem(id);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? [];
    state = AsyncData(current.where((item) => item.id != id).toList());
    await _repository.removeItem(id);
  }

  Future<void> clearCompleted() async {
    final current = state.value ?? [];
    state = AsyncData(current.where((item) => !item.done).toList());
    await _repository.clearCompletedItems();
  }
}

final todoListProvider = StreamNotifierProvider<TodoListNotifier, List<TodoItem>>(TodoListNotifier.new);

/// 미완료 항목을 앞에, 완료 항목(취소선 표시)을 뒤에 두는 화면 표시용 정렬.
/// 저장 순서(입력한 순서)는 그대로 유지해 이후 이력 조회에 영향을 주지 않는다.
List<TodoItem> sortedForDisplay(List<TodoItem> items) {
  final pending = items.where((item) => !item.done);
  final done = items.where((item) => item.done);
  return [...pending, ...done];
}

class TodoMemoNotifier extends StreamNotifier<List<MemoItem>> {
  late final TodoRepository _repository;

  // TodoListNotifier와 같은 이유로 타임스탬프에 인스턴스 카운터를 더해 id 충돌을 막는다.
  int _idSequence = 0;

  @override
  Stream<List<MemoItem>> build() {
    _repository = ref.watch(todoRepositoryProvider);
    return _repository.watchMemos();
  }

  Future<MemoItem> addMemo() async {
    final current = state.value ?? [];
    final now = DateTime.now();
    final memo = MemoItem(
      id: '${now.microsecondsSinceEpoch}-${_idSequence++}',
      title: '새 메모',
      content: '',
      createdAt: now,
      updatedAt: now,
    );
    state = AsyncData([...current, memo]);
    await _repository.addMemo(memo);
    return memo;
  }

  Future<void> renameMemo(String id, String title) async {
    final current = state.value ?? [];
    state = AsyncData([
      for (final memo in current)
        if (memo.id == id) memo.copyWith(title: title, updatedAt: DateTime.now()) else memo,
    ]);
    await _repository.renameMemo(id, title);
  }

  Future<void> updateContent(String id, String content) async {
    final current = state.value ?? [];
    state = AsyncData([
      for (final memo in current)
        if (memo.id == id) memo.copyWith(content: content, updatedAt: DateTime.now()) else memo,
    ]);
    await _repository.updateMemoContent(id, content);
  }

  Future<void> removeMemo(String id) async {
    final current = state.value ?? [];
    state = AsyncData(current.where((memo) => memo.id != id).toList());
    await _repository.removeMemo(id);
  }

  Future<void> moveMemo(String id, int delta) async {
    final current = state.value ?? [];
    final index = current.indexWhere((memo) => memo.id == id);
    if (index == -1) return;
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= current.length) return;
    final updated = [...current];
    final memo = updated.removeAt(index);
    updated.insert(newIndex, memo);
    state = AsyncData(updated);
    await _repository.moveMemo(id, delta);
  }
}

final todoMemoProvider = StreamNotifierProvider<TodoMemoNotifier, List<MemoItem>>(TodoMemoNotifier.new);
