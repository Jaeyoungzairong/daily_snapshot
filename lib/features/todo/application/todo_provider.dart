import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/cloud_list_store.dart';
import '../data/memo_item.dart';
import '../data/todo_item.dart';
import '../data/todo_repository.dart';

/// 할일/메모 문서는 Firestore 문서 하나(최대 1MiB)에 배열로 통째로 저장되므로, 개수가
/// 무한정 늘어나면 저장 자체가 실패할 수 있다. "오늘 할 일"/"빠른 메모" 용도에 맞는
/// 넉넉한 상한을 둬서 이를 방지한다.
const int maxTodoItems = 30;
const int maxMemoCount = 15;

/// 메모 한 개의 최대 글자 수. 문서 하나에 모든 메모가 함께 저장되므로, 메모 하나가
/// 지나치게 길어지는 것도 같은 이유로 제한한다.
const int maxMemoContentLength = 5000;

/// 메모 제목의 최대 글자 수. 제목은 칩(최대 120~260px)에 표시되며 어차피 그 이상은
/// 말줄임(ellipsis)으로 잘리므로, 다 보이지도 않을 만큼 길게 쓰는 것을 막는다.
const int maxMemoTitleLength = 50;

/// 할 일 한 개의 최대 글자 수. 할 일은 짧은 한 줄짜리 작업이 목적이라 메모보다 훨씬
/// 짧게 제한한다 — 목록 한 항목이 지나치게 길어져 다른 항목들을 밀어내는 것도 방지한다.
const int maxTodoTextLength = 100;

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

  /// 추가에 성공하면 true, 개수 상한(maxTodoItems)에 걸려 추가하지 않았으면 false를 반환한다.
  Future<bool> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final current = state.value ?? [];
    if (current.length >= maxTodoItems) return false;
    final item = TodoItem(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_idSequence++}',
      text: trimmed,
      done: false,
      createdAt: DateTime.now(),
    );
    // 낙관적으로 먼저 반영 — 실제 확정 값은 뒤이어 Firestore 실시간 스트림으로 들어온다.
    state = AsyncData([...current, item]);
    await _repository.addItem(item);
    return true;
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

class TodoMemoNotifier extends StreamNotifier<List<MemoItem>> {
  late final TodoRepository _repository;

  // TodoListNotifier와 같은 이유로 타임스탬프에 인스턴스 카운터를 더해 id 충돌을 막는다.
  int _idSequence = 0;

  // 제목/내용 입력을 디바운스해서 저장한다. 위젯(TodoCard)이 아니라 여기(provider)에
  // 타이머를 두는 이유는, 로그아웃 같은 동작이 위젯의 생명주기와 무관하게(AppBar 등에서)
  // 트리거될 수 있어도 [flushPending]/[cancelPendingEdits]만 호출하면 되게 하기 위함이다.
  Timer? _titleDebounce;
  Timer? _contentDebounce;
  String? _pendingTitleId;
  String? _pendingTitleValue;
  String? _pendingContentId;
  String? _pendingContentValue;

  @override
  Stream<List<MemoItem>> build() {
    _repository = ref.watch(todoRepositoryProvider);
    ref.onDispose(() {
      _titleDebounce?.cancel();
      _contentDebounce?.cancel();
    });
    return _repository.watchMemos();
  }

  /// 개수 상한(maxMemoCount)에 걸리면 추가하지 않고 null을 반환한다.
  Future<MemoItem?> addMemo() async {
    final current = state.value ?? [];
    if (current.length >= maxMemoCount) return null;
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

  /// 제목 입력을 디바운스해서 저장을 예약한다. 즉시 저장이 필요하면 [flushPending]을,
  /// 다른 메모로 전환해 지금 예약을 버려야 하면 [cancelPendingEdits]를 쓴다.
  void scheduleRename(String id, String title) {
    _pendingTitleId = id;
    _pendingTitleValue = title;
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 500), () {
      _pendingTitleId = null;
      renameMemo(id, title);
    });
  }

  void scheduleContent(String id, String content) {
    _pendingContentId = id;
    _pendingContentValue = content;
    _contentDebounce?.cancel();
    _contentDebounce = Timer(const Duration(milliseconds: 500), () {
      _pendingContentId = null;
      updateContent(id, content);
    });
  }

  /// 예약된 저장이 있으면 기다리지 않고 즉시 실행한다. 로그아웃 직전처럼, 이후로는
  /// 저장이 실패할 수 있는 시점에 마지막 편집 내용을 유실하지 않으려고 사용한다.
  Future<void> flushPending() async {
    if (_titleDebounce?.isActive ?? false) {
      _titleDebounce!.cancel();
      final id = _pendingTitleId;
      final value = _pendingTitleValue;
      _pendingTitleId = null;
      if (id != null && value != null) {
        try {
          await renameMemo(id, value);
        } catch (_) {
          // 최선을 다한 저장 시도일 뿐이라, 실패해도 호출한 쪽(로그아웃 등)은 계속 진행한다.
        }
      }
    }
    if (_contentDebounce?.isActive ?? false) {
      _contentDebounce!.cancel();
      final id = _pendingContentId;
      final value = _pendingContentValue;
      _pendingContentId = null;
      if (id != null && value != null) {
        try {
          await updateContent(id, value);
        } catch (_) {}
      }
    }
  }

  /// 예약된 저장을 저장하지 않고 취소한다(다른 메모로 전환할 때 사용).
  void cancelPendingEdits() {
    _titleDebounce?.cancel();
    _contentDebounce?.cancel();
    _pendingTitleId = null;
    _pendingContentId = null;
  }
}

final todoMemoProvider = StreamNotifierProvider<TodoMemoNotifier, List<MemoItem>>(TodoMemoNotifier.new);
