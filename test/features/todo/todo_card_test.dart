import 'package:daily_snapshot/features/todo/application/todo_provider.dart';
import 'package:daily_snapshot/features/todo/data/key_value_store.dart';
import 'package:daily_snapshot/features/todo/data/todo_repository.dart';
import 'package:daily_snapshot/features/todo/presentation/todo_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;
}

void main() {
  testWidgets('TodoCard renders, adds an item, and toggles it without overflow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todoRepositoryProvider.overrideWithValue(TodoRepository(store: _InMemoryKeyValueStore())),
        ],
        child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: TodoCard()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('오늘 할 일을 추가해보세요.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '3시 팀 미팅 자료 준비');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('3시 팀 미팅 자료 준비'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('완료 항목 지우기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
