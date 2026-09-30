import 'dart:async';

import 'package:daily_snapshot/core/auth/auth_provider.dart';
import 'package:daily_snapshot/features/todo/application/todo_provider.dart';
import 'package:daily_snapshot/features/todo/data/cloud_list_store.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:daily_snapshot/features/todo/presentation/memo_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Override 타입이 flutter_riverpod의 공개 API로 노출돼 있지 않아 반환 타입을 명시할 수 없다.
// ignore: strict_top_level_inference
_signedInOverrides() => [
  authUidProvider.overrideWith((ref) => const AsyncData('test-uid')),
  todoRepositoryProvider.overrideWithValue(TodoRepository(store: _InMemoryCloudListStore())),
];

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

/// [failing]이 true인 동안 저장이 항상 실패하는 저장소(오프라인 상황 재현용).
class _FlakyCloudListStore extends _InMemoryCloudListStore {
  bool failing = false;

  @override
  Future<void> mutate(
    String docKey,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> current) transform,
  ) async {
    if (failing) throw Exception('write failed');
    await super.mutate(docKey, transform);
  }
}

/// Firestore snapshots()처럼 구독 시 한 번 + 쓰기가 성공할 때마다 다시 내보내고, [remoteEdit]로
/// "다른 기기에서의 변경"도 흘려보낼 수 있는 저장소. 위의 _InMemoryCloudListStore는 한 번만
/// 내보내서 원격 변경 반영을 검증할 수 없다.
class _SyncingCloudListStore implements CloudListStore {
  final Map<String, List<Map<String, dynamic>>> docs = {};
  final Map<String, Set<StreamController<List<Map<String, dynamic>>>>> _listeners = {};

  @override
  Stream<List<Map<String, dynamic>>> watch(String docKey) {
    late final StreamController<List<Map<String, dynamic>>> controller;
    controller = StreamController(
      onListen: () {
        controller.add(_copy(docKey));
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
    docs[docKey] = transform(_copy(docKey));
    _emit(docKey);
  }

  /// 다른 기기에서 메모 [index]번째 항목의 필드를 바꾼 것처럼 저장하고 내보낸다.
  void remoteEdit(int index, Map<String, dynamic> fields) {
    final items = _copy('todo_memos');
    items[index] = {...items[index], ...fields};
    docs['todo_memos'] = items;
    _emit('todo_memos');
  }

  List<Map<String, dynamic>> _copy(String docKey) => [
    for (final item in docs[docKey] ?? const <Map<String, dynamic>>[]) Map.of(item),
  ];

  void _emit(String docKey) {
    for (final controller in {...?_listeners[docKey]}) {
      controller.add(_copy(docKey));
    }
  }
}

Future<_SyncingCloudListStore> _pumpMemoCardWithOneMemo(WidgetTester tester) async {
  final store = _SyncingCloudListStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUidProvider.overrideWith((ref) => const AsyncData('test-uid')),
        todoRepositoryProvider.overrideWithValue(TodoRepository(store: store)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MemoCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('새 메모 추가'));
  await tester.pumpAndSettle();
  return store;
}

TextEditingController _titleController(WidgetTester tester) =>
    tester.widget<TextField>(find.widgetWithText(TextField, '제목')).controller!;

TextEditingController _contentController(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).last).controller!;

void main() {
  // 예전엔 편집창이 처음 불러올 때/메모를 고를 때만 채워져서, 다른 기기에서 고친 메모를 옛
  // 화면에서 한 글자만 고쳐도 옛 전체 내용이 저장돼 원격 변경이 조용히 사라졌다.
  group('MemoCard syncing edits from other devices', () {
    testWidgets('follows a remote change while the user is not editing', (tester) async {
      final store = await _pumpMemoCardWithOneMemo(tester);

      store.remoteEdit(0, {'title': '폰에서 바꾼 제목', 'content': '폰에서 고친 내용'});
      await tester.pumpAndSettle();

      expect(_titleController(tester).text, '폰에서 바꾼 제목');
      expect(_contentController(tester).text, '폰에서 고친 내용');

      // 이어서 입력하면 원격 내용 위에 이어 쓴 값이 저장돼야 한다(옛 빈 내용으로 덮지 않음).
      await tester.enterText(find.byType(TextField).last, '폰에서 고친 내용 + 웹에서 추가');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(store.docs['todo_memos']!.single['content'], '폰에서 고친 내용 + 웹에서 추가');
      expect(store.docs['todo_memos']!.single['title'], '폰에서 바꾼 제목');
    });

    testWidgets('keeps the text being typed, but still follows the other field', (tester) async {
      final store = await _pumpMemoCardWithOneMemo(tester);

      // 내용 입력 직후(디바운스 대기 중)에 다른 기기에서 제목과 내용이 모두 바뀜.
      await tester.enterText(find.byType(TextField).last, '입력 중인 글');
      store.remoteEdit(0, {'title': '원격 제목', 'content': '원격 내용'});
      await tester.pump();

      expect(_contentController(tester).text, '입력 중인 글');
      expect(_titleController(tester).text, '원격 제목');

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      // 동시 편집은 나중 저장이 이긴다(알려진 한계) — 입력 중이던 글이 사라지지 않는 게 핵심.
      expect(_contentController(tester).text, '입력 중인 글');
      expect(store.docs['todo_memos']!.single['content'], '입력 중인 글');
      expect(store.docs['todo_memos']!.single['title'], '원격 제목');
    });

    testWidgets('own saves coming back do not move the text or the cursor', (tester) async {
      final store = await _pumpMemoCardWithOneMemo(tester);

      await tester.enterText(find.byType(TextField).last, '내가 쓴 글');
      _contentController(tester).selection = const TextSelection.collapsed(offset: 2);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(store.docs['todo_memos']!.single['content'], '내가 쓴 글');
      expect(_contentController(tester).text, '내가 쓴 글');
      expect(_contentController(tester).selection, const TextSelection.collapsed(offset: 2));

      // 저장이 반영된 뒤(기준값 갱신)에 온 원격 변경은 다시 따라가고, 커서 위치도 유지된다.
      store.remoteEdit(0, {'content': '원격에서 바뀐 글'});
      await tester.pumpAndSettle();
      expect(_contentController(tester).text, '원격에서 바뀐 글');
      expect(_contentController(tester).selection, const TextSelection.collapsed(offset: 2));
    });
  });

  testWidgets('MemoCard keeps an unsaved-changes banner until a retry succeeds', (tester) async {
    final store = _FlakyCloudListStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUidProvider.overrideWith((ref) => const AsyncData('test-uid')),
          todoRepositoryProvider.overrideWithValue(TodoRepository(store: store)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MemoCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('새 메모 추가'));
    await tester.pumpAndSettle();

    store.failing = true;
    await tester.enterText(find.widgetWithText(TextField, '제목'), '오프라인 제목');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('저장되지 않은 메모 변경 사항이 있습니다.'), findsOneWidget);

    store.failing = false;
    await tester.tap(find.text('다시 저장'));
    await tester.pumpAndSettle();

    expect(find.text('저장되지 않은 메모 변경 사항이 있습니다.'), findsNothing);
    expect(find.text('메모를 저장했습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MemoCard adds a memo, renames it, edits content, and deletes it without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _signedInOverrides(),
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: MemoCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('메모가 없습니다. + 버튼을 눌러 추가해보세요.'), findsOneWidget);

    await tester.tap(find.byTooltip('새 메모 추가'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('메모 삭제'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '제목'), '회의록');
    await tester.enterText(find.byType(TextField).last, '오늘 논의 내용');
    await tester.pumpAndSettle();

    expect(find.text('회의록'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('메모 삭제'));
    await tester.tap(find.byTooltip('메모 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('메모 삭제'), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('메모가 없습니다. + 버튼을 눌러 추가해보세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
