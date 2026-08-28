import 'package:daily_snapshot/features/shortcuts/presentation/shortcuts_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ShortcutsCard renders all configured links without overflow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ShortcutsCard()))),
    );
    await tester.pumpAndSettle();

    expect(find.text('그룹웨어'), findsOneWidget);
    expect(find.text('NAS 서버'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Naver'), findsOneWidget);
    expect(find.text('네이버지도'), findsOneWidget);
    expect(find.text('카카오맵'), findsOneWidget);
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('구글 드라이브'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
