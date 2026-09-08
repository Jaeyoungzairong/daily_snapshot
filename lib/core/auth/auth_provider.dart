import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Firebase 로그인 상태를 구독하는 유일한 지점. uid/email/isAdmin 등 파생 provider들은
/// authStateChanges()를 각자 새로 구독하지 않고 전부 이 provider가 이미 캐시해둔 현재
/// 값에서 파생시킨다 — authStateChanges()는 일반 브로드캐스트 스트림이라, 이미 지나간
/// "로그인 복원" 이벤트는 뒤늦게 구독한 쪽에 다시 전달되지 않아 영원히 대기하게 된다
/// (실제로 이 문제로 파일 업로드 시 이메일을 못 읽어와 조용히 멈추는 버그가 있었다).
/// riverpod의 watch는 새 구독자에게도 캐시된 현재 값을 즉시 돌려주므로 이 문제가 없다.
final _authUserProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).userChanges();
});

/// 로그인 안 됐으면 null. 화면 쪽에서는 firebase_auth의 User 타입을 직접 다룰 필요가
/// 없도록(테스트에서 가짜 User를 만드는 번거로움을 피하려고) uid만 노출한다.
final authUidProvider = Provider<AsyncValue<String?>>((ref) {
  return ref.watch(_authUserProvider).whenData((user) => user?.uid);
});

/// 로그인 안 됐으면 null.
final authEmailProvider = Provider<AsyncValue<String?>>((ref) {
  return ref.watch(_authUserProvider).whenData((user) => user?.email);
});

/// 로그인한 사용자가 관리자(admin_allowed_emails 문서의 isAdmin:true)인지.
final isAdminProvider = StreamProvider<bool>((ref) {
  final email = ref.watch(authEmailProvider).value;
  if (email == null) return Stream.value(false);
  return ref.watch(authServiceProvider).watchIsAdmin(email);
});
