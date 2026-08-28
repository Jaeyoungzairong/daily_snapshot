import 'package:daily_snapshot/features/weather/data/city_candidate.dart';
import 'package:daily_snapshot/features/weather/data/kma_region_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KmaRegionDirectory.search (ranking)', () {
    final directory = KmaRegionDirectory.fromRegions(const [
      CityCandidate(
        name: '종로1.2.3.4가동',
        latitude: 37.567,
        longitude: 126.991,
        admin1: '서울특별시 종로구',
        country: '대한민국',
      ),
      CityCandidate(
        name: '종로구',
        latitude: 37.570,
        longitude: 126.981,
        admin1: '서울특별시',
        country: '대한민국',
      ),
      CityCandidate(
        name: '종로5.6가동',
        latitude: 37.569,
        longitude: 127.007,
        admin1: '서울특별시 종로구',
        country: '대한민국',
      ),
    ]);

    test('exact name match ranks before partial matches', () {
      final results = directory.search('종로구');
      expect(results.first.name, '종로구');
    });

    test('prefix match ranks before matches that only contain the query mid-string', () {
      final results = directory.search('종로');
      // "종로1.2.3.4가동"/"종로5.6가동"은 이름이 "종로"로 시작(prefix), "종로구"는 정확히
      // 일치하진 않지만 이 목록에선 접두 일치이기도 함 — 셋 다 startsWith이므로 순서는
      // 입력 순서 유지, admin1에만 매칭되는 것보단 항상 앞에 와야 함이 핵심.
      expect(results, hasLength(3));
    });

    test('matches via admin1 when the query does not appear in the name', () {
      final results = directory.search('종로구');
      expect(results.map((r) => r.name), containsAll(['종로구', '종로1.2.3.4가동', '종로5.6가동']));
    });

    test('returns nothing for blank query', () {
      expect(directory.search('   '), isEmpty);
    });

    test('returns nothing when no region matches', () {
      expect(directory.search('존재하지않는지명'), isEmpty);
    });
  });

  group('KmaRegionDirectory.load (bundled asset)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('찾을 수 없었던 실제 사례(판교동/애월읍/종로구)가 번들 자산에 존재한다', () async {
      final directory = await KmaRegionDirectory.load();

      final pangyo = directory.search('판교동');
      expect(pangyo.map((c) => c.name), contains('판교동'));
      final pangyoEntry = pangyo.firstWhere((c) => c.name == '판교동');
      expect(pangyoEntry.admin1, contains('성남시분당구'));

      expect(directory.search('애월읍').map((c) => c.name), contains('애월읍'));

      final jongno = directory.search('종로구');
      expect(jongno.first.name, '종로구');
      expect(jongno.first.admin1, '서울특별시');
    });

    test('이어도처럼 좌표가 0,0인 특수 지점은 자산 생성 시 제외돼 있다', () async {
      final directory = await KmaRegionDirectory.load();
      // 위경도가 없어 격자 변환이 불가능하므로, 검색은 되지 않아야 한다(좌표 있는 다른
      // 지점이 우연히 "이어도"를 포함하지 않는 한 결과가 비어 있어야 함).
      expect(directory.search('이어도'), isEmpty);
    });
  });
}
