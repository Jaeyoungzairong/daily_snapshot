// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'location_exception.dart';

/// 브라우저 Geolocation API로 현재 좌표를 1회 조회한다(지속 추적 아님).
/// HTTPS(또는 localhost)에서만 동작하며, 사용자가 권한을 거부하거나 응답이 없으면
/// [LocationException]을 던진다.
Future<({double latitude, double longitude})> getCurrentPosition() async {
  try {
    final position = await html.window.navigator.geolocation
        .getCurrentPosition(enableHighAccuracy: false, timeout: const Duration(seconds: 8))
        .timeout(const Duration(seconds: 10));

    final lat = position.coords?.latitude;
    final lng = position.coords?.longitude;
    if (lat == null || lng == null) {
      throw const LocationException('위치 정보를 가져올 수 없습니다.');
    }
    return (latitude: lat.toDouble(), longitude: lng.toDouble());
  } on LocationException {
    rethrow;
  } catch (_) {
    throw const LocationException('위치 정보를 가져올 수 없습니다. 브라우저 위치 권한을 확인해주세요.');
  }
}
