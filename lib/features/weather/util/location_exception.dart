/// 브라우저 위치 조회 실패(권한 거부, 시간 초과, 플랫폼 미지원 등)를 나타낸다.
class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => message;
}
