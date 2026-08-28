import 'package:daily_snapshot/features/shortcuts/presentation/shortcuts_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ShortcutsCard renders all configured links without overflow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ShortcutsCard()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('다우오피스'), findsOneWidget);
    expect(find.text('사내 시스템'), findsOneWidget);
    expect(find.text('구글 드라이브'), findsOneWidget);
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('구글'), findsOneWidget);
    expect(find.text('네이버'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
