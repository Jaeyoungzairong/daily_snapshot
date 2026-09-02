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

  Stream<List<TodoItem>> watchItems() {
    return _store.watch(_itemsDoc).map((raw) => raw.map(TodoItem.fromJson).toList());
  }

  Future<void> addItem(TodoItem item) => _mutateItems((items) => [...items, item]);

  Future<void> toggleItem(String id) => _mutateItems((items) => [
        for (final item in items)
          if (item.id == id)
            item.copyWith(done: !item.done, completedAt: item.done ? null : DateTime.now())
          else
            item,
      ]);

  Future<void> removeItem(String id) => _mutateItems((items) => items.where((item) => item.id != id).toList());

  Future<void> clearCompletedItems() => _mutateItems((items) => items.where((item) => !item.done).toList());

  Future<void> _mutateItems(List<TodoItem> Function(List<TodoItem> current) transform) {
    return _store.mutate(
      _itemsDoc,
      (raw) => transform(raw.map(TodoItem.fromJson).toList()).map((e) => e.toJson()).toList(),
    );
  }

  Stream<List<MemoItem>> watchMemos() {
    return _store.watch(_memosDoc).map((raw) => raw.map(MemoItem.fromJson).toList());
  }

  Future<void> addMemo(MemoItem memo) => _mutateMemos((memos) => [...memos, memo]);

  Future<void> renameMemo(String id, String title) => _mutateMemos((memos) => [
        for (final memo in memos)
          if (memo.id == id) memo.copyWith(title: title, updatedAt: DateTime.now()) else memo,
      ]);

  Future<void> updateMemoContent(String id, String content) => _mutateMemos((memos) => [
        for (final memo in memos)
          if (memo.id == id) memo.copyWith(content: content, updatedAt: DateTime.now()) else memo,
      ]);

  Future<void> removeMemo(String id) => _mutateMemos((memos) => memos.where((memo) => memo.id != id).toList());

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
    return _store.mutate(
      _memosDoc,
      (raw) => transform(raw.map(MemoItem.fromJson).toList()).map((e) => e.toJson()).toList(),
    );
  }
}
