import 'package:daily_snapshot/features/dashboard/presentation/dashboard_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dashboardGridCardWidth', () {
    // 페이지 좌우 패딩 16*2 + 카드 사이 간격 16을 빼고 반으로 나눈 폭이 2열이 들어가는 조건.
    bool twoColumnsFit(double viewportWidth) {
      final cardWidth = dashboardGridCardWidth(viewportWidth);
      return cardWidth * 2 + 16 <= viewportWidth - 32;
    }

    test('two cards fit side by side at every width from the 900px breakpoint upward', () {
      for (var width = 900.0; width <= 2000; width += 0.7) {
        expect(twoColumnsFit(width), isTrue, reason: 'width $width');
      }
    });

    test('shrinks to fill the row just above the breakpoint instead of leaving a 560px column', () {
      // 예전에는 900px에서도 560px 고정이라 한 줄에 카드 하나만 들어갔다.
      expect(dashboardGridCardWidth(900), 426);
    });

    test('caps at 560px on wide screens', () {
      expect(dashboardGridCardWidth(1168), 560);
      expect(dashboardGridCardWidth(1920), 560);
    });
  });
}
