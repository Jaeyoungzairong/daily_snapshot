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

void main() {
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
