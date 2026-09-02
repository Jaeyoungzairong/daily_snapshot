import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// 로그인 안 됐으면 null. 화면 쪽에서는 firebase_auth의 User 타입을 직접 다룰 필요가
/// 없도록(테스트에서 가짜 User를 만드는 번거로움을 피하려고) uid만 노출한다.
final authUidProvider = StreamProvider<String?>((ref) {
  return ref.watch(authServiceProvider).uidChanges();
});
