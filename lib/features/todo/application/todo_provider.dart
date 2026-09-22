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

/// 낙관적으로 화면 상태를 먼저 바꾼 뒤 Firestore에 쓰는 Notifier들의 공통 동작.
///
/// 쓰기가 실패하면 이 커밋 직전의 state.value(previous)로 되돌린다. previous는 그 이전
/// 커밋들의 결과(성공한 낙관적 반영이든, 실패 후 롤백이든, 그사이 도착한 실제 서버 값이든)를
/// 이미 반영한 값이라, 매 커밋이 각자 이렇게만 되돌려도 연쇄 실패에서 상태가 계속 정확하게
/// 유지된다. 스트림이 나중에 보내는 확정 값이 도착하면 그걸로 자연히 덮어써진다. 예외는
/// 그대로 다시 던져서 호출한 쪽(UI)이 사용자에게 알릴 수 있게 한다.
mixin _OptimisticList<T> on StreamNotifier<List<T>> {
  Future<void> _commit(List<T> optimistic, Future<void> Function() write) async {
    final previous = state.value;
    state = AsyncData(optimistic);
    try {
      await write();
    } catch (_) {
      if (ref.mounted && previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

class TodoListNotifier extends StreamNotifier<List<TodoItem>> with _OptimisticList<TodoItem> {
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
  /// 저장에 실패하면 예외를 던진다(화면 상태는 서버 값으로 복구됨).
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
    await _commit([...current, item], () => _repository.addItem(item));
    return true;
  }

  Future<void> toggle(String id) async {
    final current = state.value ?? [];
    await _commit([
      for (final item in current)
        if (item.id == id)
          item.copyWith(done: !item.done, completedAt: item.done ? null : DateTime.now())
        else
          item,
    ], () => _repository.toggleItem(id));
  }

  Future<void> remove(String id) async {
    final current = state.value ?? [];
    await _commit(
      current.where((item) => item.id != id).toList(),
      () => _repository.removeItem(id),
    );
  }

  Future<void> clearCompleted() async {
    final current = state.value ?? [];
    await _commit(
      current.where((item) => !item.done).toList(),
      _repository.clearCompletedItems,
    );
  }
}

final todoListProvider = StreamNotifierProvider<TodoListNotifier, List<TodoItem>>(
  TodoListNotifier.new,
);

/// 디바운스로 예약된 메모 자동저장이 "실패 상태로 바뀔 때마다" 1씩 늘어나는 카운터.
/// 타이머 콜백에서 난 실패는 호출한 화면이 없어 예외로 전달할 수 없으므로, UI(MemoCard)가
/// 이 값의 변화를 듣고 안내한다. 이미 실패 상태인 채로 반복되는 실패는 세지 않고(안내
/// 반복 방지), 저장이 다시 성공한 뒤 새로 실패하면 다시 센다.
class MemoSaveFailureNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void notifyFailure() => state++;
}

final memoSaveFailureProvider = NotifierProvider<MemoSaveFailureNotifier, int>(
  MemoSaveFailureNotifier.new,
);

class TodoMemoNotifier extends StreamNotifier<List<MemoItem>> with _OptimisticList<MemoItem> {
  late final TodoRepository _repository;

  // TodoListNotifier와 같은 이유로 타임스탬프에 인스턴스 카운터를 더해 id 충돌을 막는다.
  int _idSequence = 0;

  // 제목/내용 입력을 디바운스해서 저장한다. 위젯(TodoCard)이 아니라 여기(provider)에
  // 타이머를 두는 이유는, 로그아웃 같은 동작이 위젯의 생명주기와 무관하게(AppBar 등에서)
  // 트리거될 수 있어도 [flushPending]/[cancelPendingEdits]만 호출하면 되게 하기 위함이다.
  static const Duration _debounceDelay = Duration(milliseconds: 500);
  Timer? _titleDebounce;
  Timer? _contentDebounce;
  bool _titleSaveFailed = false;
  bool _contentSaveFailed = false;
  bool _failureReported = false;
  String? _pendingTitleId;
  String? _pendingTitleValue;
  String? _pendingContentId;
  String? _pendingContentValue;

  @override
  Stream<List<MemoItem>> build() {
    _repository = ref.watch(todoRepositoryProvider);
    // 저장 실패로 남아 있던 이전 사용자의 대기 값이 다른 계정 문서에 쓰이지 않도록 초기화한다.
    _pendingTitleId = null;
    _pendingTitleValue = null;
    _pendingContentId = null;
    _pendingContentValue = null;
    _titleSaveFailed = false;
    _contentSaveFailed = false;
    _failureReported = false;
    ref.onDispose(() {
      _titleDebounce?.cancel();
      _contentDebounce?.cancel();
    });
    return _repository.watchMemos();
  }

  /// 개수 상한(maxMemoCount)에 걸리면 추가하지 않고 null을 반환한다. 저장에 실패하면
  /// 예외를 던진다(화면 상태는 서버 값으로 복구됨).
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
    await _commit([...current, memo], () => _repository.addMemo(memo));
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
    await _commit(
      current.where((memo) => memo.id != id).toList(),
      () => _repository.removeMemo(id),
    );
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
    await _commit(updated, () => _repository.moveMemo(id, delta));
  }

  /// 제목 입력을 디바운스해서 저장을 예약한다. 즉시 저장이 필요하면 [flushPending]을,
  /// 다른 메모로 전환해 지금 예약을 버려야 하면 [cancelPendingEdits]를 쓴다.
  void scheduleRename(String id, String title) {
    _pendingTitleId = id;
    _pendingTitleValue = title;
    _titleDebounce?.cancel();
    _titleDebounce = Timer(_debounceDelay, _savePendingTitle);
  }

  void scheduleContent(String id, String content) {
    _pendingContentId = id;
    _pendingContentValue = content;
    _contentDebounce?.cancel();
    _contentDebounce = Timer(_debounceDelay, _savePendingContent);
  }

  // 저장에 실패하면 대기 값을 지우지 않고 남겨둔다 — 이후 [flushPending](메모 전환,
  // 로그아웃)이 한 번 더 재시도할 수 있게 하기 위함이다. 성공했을 때도 저장하는 동안 사용자가
  // 더 입력해 대기 값이 바뀌었다면 그 새 값은 지우지 않는다.
  Future<void> _savePendingTitle() async {
    final id = _pendingTitleId;
    final value = _pendingTitleValue;
    if (id == null || value == null) return;
    try {
      await renameMemo(id, value);
      if (_pendingTitleId == id && _pendingTitleValue == value) {
        _pendingTitleId = null;
        _pendingTitleValue = null;
      }
      _titleSaveFailed = false;
    } catch (_) {
      _titleSaveFailed = true;
    }
    _publishSaveFailure();
  }

  Future<void> _savePendingContent() async {
    final id = _pendingContentId;
    final value = _pendingContentValue;
    if (id == null || value == null) return;
    try {
      await updateContent(id, value);
      if (_pendingContentId == id && _pendingContentValue == value) {
        _pendingContentId = null;
        _pendingContentValue = null;
      }
      _contentSaveFailed = false;
    } catch (_) {
      _contentSaveFailed = true;
    }
    _publishSaveFailure();
  }

  void _publishSaveFailure() {
    final failed = _titleSaveFailed || _contentSaveFailed;
    final newlyFailed = failed && !_failureReported;
    _failureReported = failed;
    if (newlyFailed && ref.mounted) ref.read(memoSaveFailureProvider.notifier).notifyFailure();
  }

  /// 예약된(또는 이전에 저장에 실패해 남아 있는) 저장을 기다리지 않고 즉시 실행한다.
  /// 로그아웃 직전처럼, 이후로는 저장이 실패할 수 있는 시점에 마지막 편집 내용을 유실하지
  /// 않으려고 사용한다. 최선을 다한 시도라 저장이 실패해도 예외를 던지지 않고(호출한
  /// 쪽의 로그아웃 등은 계속 진행), 실패는 [memoSaveFailureProvider]로 알린다.
  Future<void> flushPending() async {
    _titleDebounce?.cancel();
    _contentDebounce?.cancel();
    await _savePendingTitle();
    await _savePendingContent();
  }

  /// 예약된 저장을 저장하지 않고 취소한다(다른 메모로 전환할 때 사용).
  void cancelPendingEdits() {
    _titleDebounce?.cancel();
    _contentDebounce?.cancel();
    _pendingTitleId = null;
    _pendingTitleValue = null;
    _pendingContentId = null;
    _pendingContentValue = null;
    _titleSaveFailed = false;
    _contentSaveFailed = false;
    _publishSaveFailure();
  }
}

final todoMemoProvider = StreamNotifierProvider<TodoMemoNotifier, List<MemoItem>>(
  TodoMemoNotifier.new,
);
