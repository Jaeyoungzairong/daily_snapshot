import 'package:daily_snapshot/core/auth/auth_provider.dart';
import 'package:daily_snapshot/core/config/app_version_provider.dart';
import 'package:daily_snapshot/features/dashboard/presentation/dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Dashboard adds the navigation bar height below the content so the version is not hidden',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      // 하단 네비게이션 바 48dp를 흉내 낸다(3배율 → 물리 픽셀 144).
      tester.view.padding = const FakeViewPadding(bottom: 144);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUidProvider.overrideWithValue(const AsyncData(null)),
            authEmailProvider.overrideWithValue(const AsyncData(null)),
            appVersionProvider.overrideWithValue(const AsyncData('26.9.28')),
          ],
          child: const MaterialApp(home: DashboardPage()),
        ),
      );
      await tester.pump();

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byWidgetPredicate(
          (widget) => widget is SingleChildScrollView && widget.padding != null,
        ),
      );
      expect((scrollView.padding! as EdgeInsets).bottom, 16 + 48);
    },
  );
}
