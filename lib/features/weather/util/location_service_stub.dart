import 'location_exception.dart';

Future<({double latitude, double longitude})> getCurrentPosition() {
  throw const LocationException('이 플랫폼에서는 위치 조회를 지원하지 않습니다.');
}
