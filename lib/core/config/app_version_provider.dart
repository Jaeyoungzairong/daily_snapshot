import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 버전(`v1.2.3+4` 형태로 표시)을 웹/안드로이드 양쪽에서 같은 방식으로 가져온다.
/// 안드로이드는 설치된 APK의 실제 versionName+versionCode를, 웹은 `flutter build web`이
/// 빌드 시점에 자동 생성하는 `build/web/version.json`을 읽는다 — 둘 다 `pubspec.yaml`의
/// `version`이 출처라, CI/로컬 빌드 스크립트가 별도로 값을 주입해줄 필요가 없다.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
});
