import 'dart:convert';

import 'key_value_store.dart';
import 'todo_item.dart';

/// 할 일 목록/메모를 로컬에 저장·조회한다. 백엔드가 없는 정적 웹 배포라
/// 브라우저 로컬 저장소(SharedPreferencesAsync, 웹에서는 localStorage)가 유일한 저장 수단이다.
class TodoRepository {
  TodoRepository({KeyValueStore? store}) : _store = store ?? SharedPreferencesKeyValueStore();

  final KeyValueStore _store;

  static const String _itemsKey = 'todo_items';
  static const String _memoKey = 'todo_memo';

  Future<List<TodoItem>> loadItems() async {
    final raw = await _store.getString(_itemsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.map((e) => TodoItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveItems(List<TodoItem> items) {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    return _store.setString(_itemsKey, encoded);
  }

  Future<String> loadMemo() async {
    return await _store.getString(_memoKey) ?? '';
  }

  Future<void> saveMemo(String memo) {
    return _store.setString(_memoKey, memo);
  }
}
