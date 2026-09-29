import 'cloud_list_store.dart';
import 'memo_item.dart';
import 'todo_item.dart';

/// 할 일/메모를 Firestore에 저장·조회한다(기기 간 동기화를 위해 [CloudListStore]를 씀).
/// 도시 선택/다크모드처럼 이 기기에만 있으면 되는 값은 여전히 로컬 저장소를 쓰고,
/// 할 일/메모만 이 리포지토리를 거친다.
class TodoRepository {
  // ignore: prefer_initializing_formals
  TodoRepository({required CloudListStore store}) : _store = store;

  final CloudListStore _store;

  static const String _itemsDoc = 'todo_items';
  static const String _memosDoc = 'todo_memos';

  // 문서 하나에 항목 전체가 배열로 들어 있어, 항목 하나라도 필드가 빠졌거나 타입이 다르면(예:
  // Firebase 콘솔에서 수동 편집) 예전엔 스트림 전체가 에러가 돼 카드가 통째로 마비됐고 "다시
  // 시도"로도 복구되지 않았다. 읽을 수 없는 항목만 건너뛰어 나머지는 정상 표시한다.
  Stream<List<T>> _watch<T>(String docKey, T Function(Map<String, dynamic>) fromJson) {
    return _store.watch(docKey).map((raw) {
      final readable = <T>[];
      for (final entry in raw) {
        try {
          readable.add(fromJson(entry));
        } catch (_) {}
      }
      return readable;
    });
  }

  // 읽을 수 없는 항목은 화면에 보이지 않지만 저장할 때 지우지 않고 그대로 뒤에 붙여 보존한다 —
  // 지워버리면 수동으로 고쳐 살릴 수 있었던 데이터를 앱이 조용히 삭제하게 된다.
  Future<void> _mutate<T>(
    String docKey,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, dynamic> Function(T) toJson,
    List<T> Function(List<T> current) transform,
  ) {
    return _store.mutate(docKey, (raw) {
      final readable = <T>[];
      final unreadable = <Map<String, dynamic>>[];
      for (final entry in raw) {
        try {
          readable.add(fromJson(entry));
        } catch (_) {
          unreadable.add(entry);
        }
      }
      return [...transform(readable).map(toJson), ...unreadable];
    });
  }

  Stream<List<TodoItem>> watchItems() => _watch(_itemsDoc, TodoItem.fromJson);

  Future<void> addItem(TodoItem item) => _mutateItems((items) => [...items, item]);

  Future<void> toggleItem(String id) => _mutateItems(
    (items) => [
      for (final item in items)
        if (item.id == id)
          item.copyWith(done: !item.done, completedAt: item.done ? null : DateTime.now())
        else
          item,
    ],
  );

  Future<void> removeItem(String id) =>
      _mutateItems((items) => items.where((item) => item.id != id).toList());

  Future<void> clearCompletedItems() =>
      _mutateItems((items) => items.where((item) => !item.done).toList());

  Future<void> _mutateItems(List<TodoItem> Function(List<TodoItem> current) transform) {
    return _mutate(_itemsDoc, TodoItem.fromJson, (item) => item.toJson(), transform);
  }

  Stream<List<MemoItem>> watchMemos() => _watch(_memosDoc, MemoItem.fromJson);

  Future<void> addMemo(MemoItem memo) => _mutateMemos((memos) => [...memos, memo]);

  Future<void> renameMemo(String id, String title) => _mutateMemos(
    (memos) => [
      for (final memo in memos)
        if (memo.id == id) memo.copyWith(title: title, updatedAt: DateTime.now()) else memo,
    ],
  );

  Future<void> updateMemoContent(String id, String content) => _mutateMemos(
    (memos) => [
      for (final memo in memos)
        if (memo.id == id) memo.copyWith(content: content, updatedAt: DateTime.now()) else memo,
    ],
  );

  Future<void> removeMemo(String id) =>
      _mutateMemos((memos) => memos.where((memo) => memo.id != id).toList());

  Future<void> moveMemo(String id, int delta) => _mutateMemos((memos) {
    final index = memos.indexWhere((memo) => memo.id == id);
    if (index == -1) return memos;
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= memos.length) return memos;
    final updated = [...memos];
    final memo = updated.removeAt(index);
    updated.insert(newIndex, memo);
    return updated;
  });

  Future<void> _mutateMemos(List<MemoItem> Function(List<MemoItem> current) transform) {
    return _mutate(_memosDoc, MemoItem.fromJson, (memo) => memo.toJson(), transform);
  }
}
