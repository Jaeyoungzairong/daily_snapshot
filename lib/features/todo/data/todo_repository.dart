import 'dart:convert';

import 'key_value_store.dart';
import 'memo_item.dart';
import 'todo_item.dart';

/// 할 일 목록/메모를 로컬에 저장·조회한다. 백엔드가 없는 정적 웹 배포라
/// 브라우저 로컬 저장소(SharedPreferencesAsync, 웹에서는 localStorage)가 유일한 저장 수단이다.
class TodoRepository {
  TodoRepository({KeyValueStore? store}) : _store = store ?? SharedPreferencesKeyValueStore();

  final KeyValueStore _store;

  static const String _itemsKey = 'todo_items';
  static const String _memosKey = 'todo_memos';
  // 메모를 여러 개 둘 수 있도록 바뀌기 전, 문자열 하나로 저장하던 옛 키.
  // 새 키가 아직 없을 때 딱 한 번만 이 값을 읽어 리스트의 첫 항목으로 이관한다.
  static const String _legacyMemoKey = 'todo_memo';

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

  Future<List<MemoItem>> loadMemos() async {
    final raw = await _store.getString(_memosKey);
    if (raw != null) {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => MemoItem.fromJson(e as Map<String, dynamic>)).toList();
    }

    final legacy = await _store.getString(_legacyMemoKey);
    final migrated = (legacy == null || legacy.isEmpty)
        ? <MemoItem>[]
        : [
            MemoItem(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              title: '메모',
              content: legacy,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          ];
    await saveMemos(migrated);
    if (legacy != null) await _store.remove(_legacyMemoKey);
    return migrated;
  }

  Future<void> saveMemos(List<MemoItem> memos) {
    final encoded = jsonEncode(memos.map((e) => e.toJson()).toList());
    return _store.setString(_memosKey, encoded);
  }
}
