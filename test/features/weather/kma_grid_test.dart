import 'package:daily_snapshot/features/weather/data/kma_grid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KmaGrid.fromLatLon', () {
    test('matches the official reference grid for Seoul city hall (60, 127)', () {
      final grid = KmaGrid.fromLatLon(latitude: 37.5665, longitude: 126.9780);
      expect(grid.nx, 60);
      expect(grid.ny, 127);
    });

    test('matches the official reference grid for Busan city hall (98, 76)', () {
      final grid = KmaGrid.fromLatLon(latitude: 35.1796, longitude: 129.0756);
      expect(grid.nx, 98);
      expect(grid.ny, 76);
    });
  });
}
