import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/memo_item.dart';
import '../data/todo_item.dart';
import '../data/todo_repository.dart';

final todoRepositoryProvider = Provider<TodoRepository>((ref) => TodoRepository());

class TodoListNotifier extends AsyncNotifier<List<TodoItem>> {
  late final TodoRepository _repository;

  // 타임스탬프만으로는 같은 마이크로초에 연달아 추가될 경우 id가 겹칠 수 있어
  // (예: 테스트에서 add()를 연속 호출) 인스턴스 수명 동안 증가만 하는 카운터를 더한다.
  int _idSequence = 0;

  @override
  Future<List<TodoItem>> build() async {
    _repository = ref.watch(todoRepositoryProvider);
    return _repository.loadItems();
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
    await _persist([...current, item]);
  }

  Future<void> toggle(String id) async {
    final current = state.value ?? [];
    final updated = [
      for (final item in current)
        if (item.id == id)
          item.copyWith(done: !item.done, completedAt: item.done ? null : DateTime.now())
        else
          item,
    ];
    await _persist(updated);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? [];
    await _persist(current.where((item) => item.id != id).toList());
  }

  Future<void> clearCompleted() async {
    final current = state.value ?? [];
    await _persist(current.where((item) => !item.done).toList());
  }

  Future<void> _persist(List<TodoItem> items) async {
    state = AsyncData(items);
    await _repository.saveItems(items);
  }
}

final todoListProvider = AsyncNotifierProvider<TodoListNotifier, List<TodoItem>>(TodoListNotifier.new);

/// 미완료 항목을 앞에, 완료 항목(취소선 표시)을 뒤에 두는 화면 표시용 정렬.
/// 저장 순서(입력한 순서)는 그대로 유지해 이후 이력 조회에 영향을 주지 않는다.
List<TodoItem> sortedForDisplay(List<TodoItem> items) {
  final pending = items.where((item) => !item.done);
  final done = items.where((item) => item.done);
  return [...pending, ...done];
}

class TodoMemoNotifier extends AsyncNotifier<List<MemoItem>> {
  late final TodoRepository _repository;

  // TodoListNotifier와 같은 이유로 타임스탬프에 인스턴스 카운터를 더해 id 충돌을 막는다.
  int _idSequence = 0;

  @override
  Future<List<MemoItem>> build() async {
    _repository = ref.watch(todoRepositoryProvider);
    return _repository.loadMemos();
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
    await _persist([...current, memo]);
    return memo;
  }

  Future<void> renameMemo(String id, String title) async {
    final current = state.value ?? [];
    final updated = [
      for (final memo in current)
        if (memo.id == id) memo.copyWith(title: title, updatedAt: DateTime.now()) else memo,
    ];
    await _persist(updated);
  }

  Future<void> updateContent(String id, String content) async {
    final current = state.value ?? [];
    final updated = [
      for (final memo in current)
        if (memo.id == id) memo.copyWith(content: content, updatedAt: DateTime.now()) else memo,
    ];
    await _persist(updated);
  }

  Future<void> removeMemo(String id) async {
    final current = state.value ?? [];
    await _persist(current.where((memo) => memo.id != id).toList());
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
    await _persist(updated);
  }

  Future<void> _persist(List<MemoItem> memos) async {
    state = AsyncData(memos);
    await _repository.saveMemos(memos);
  }
}

final todoMemoProvider = AsyncNotifierProvider<TodoMemoNotifier, List<MemoItem>>(TodoMemoNotifier.new);
