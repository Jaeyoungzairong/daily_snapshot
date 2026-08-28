import 'dart:math' as math;

/// 기상청 격자(nx, ny) 좌표.
class KmaGrid {
  const KmaGrid({required this.nx, required this.ny});

  final int nx;
  final int ny;

  /// 위경도를 기상청 단기예보 API가 쓰는 격자 좌표로 변환한다.
  /// 기상청이 공식 배포하는 람베르트 정각원추도법(LCC) 변환 공식이며, 상수값은
  /// 기상청 "기상자료개방포털" 격자-경위도 변환 프로그램(C 예제)의 값을 그대로 따른다.
  factory KmaGrid.fromLatLon({required double latitude, required double longitude}) {
    const re = 6371.00877; // 지구 반경(km)
    const grid = 5.0; // 격자 간격(km)
    const slat1 = 30.0; // 표준위도1
    const slat2 = 60.0; // 표준위도2
    const olon = 126.0; // 기준점 경도
    const olat = 38.0; // 기준점 위도
    const xo = 43.0; // 기준점 X좌표
    const yo = 136.0; // 기준점 Y좌표

    final degrad = math.pi / 180.0;
    final re2 = re / grid;
    final slat1r = slat1 * degrad;
    final slat2r = slat2 * degrad;
    final olonr = olon * degrad;
    final olatr = olat * degrad;

    var sn = math.tan(math.pi * 0.25 + slat2r * 0.5) / math.tan(math.pi * 0.25 + slat1r * 0.5);
    sn = math.log(math.cos(slat1r) / math.cos(slat2r)) / math.log(sn);
    var sf = math.tan(math.pi * 0.25 + slat1r * 0.5);
    sf = math.pow(sf, sn) * math.cos(slat1r) / sn;
    var ro = math.tan(math.pi * 0.25 + olatr * 0.5);
    ro = re2 * sf / math.pow(ro, sn);

    final latr = latitude * degrad;
    final lonr = longitude * degrad;

    var ra = math.tan(math.pi * 0.25 + latr * 0.5);
    ra = re2 * sf / math.pow(ra, sn);
    var theta = lonr - olonr;
    if (theta > math.pi) theta -= 2.0 * math.pi;
    if (theta < -math.pi) theta += 2.0 * math.pi;
    theta *= sn;

    final x = (ra * math.sin(theta) + xo + 0.5).floor();
    final y = (ro - ra * math.cos(theta) + yo + 0.5).floor();

    return KmaGrid(nx: x, ny: y);
  }
}
