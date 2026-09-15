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

final _forceLogoutAfterProvider = StreamProvider<DateTime?>((ref) {
  final email = ref.watch(authEmailProvider).value;
  if (email == null) return Stream.value(null);
  return ref.watch(authServiceProvider).watchForceLogoutAfter(email);
});

/// 이 세션(이 기기의 이 로그인)이 "다른 모든 기기에서 로그아웃"으로 무효화되지 않았는지.
/// Firestore/Storage 규칙이 실제 접근을 거부할 때까지 기다리면(재시도 백오프 때문에)
/// 체감상 로그아웃까지 시간이 걸려서, admin_allowed_emails 문서를 직접 구독해 더 빠르게
/// 반응한다. forceLogoutAfter나 로그인 시각을 아직 모르면(로딩 중) 무효로 단정하지 않고
/// true(유효함)로 취급한다 — 어차피 실제 권한은 서버 규칙이 최종적으로 판단한다.
final isSessionValidProvider = Provider<bool>((ref) {
  final forceLogoutAfter = ref.watch(_forceLogoutAfterProvider).value;
  if (forceLogoutAfter == null) return true;
  final lastSignInTime = ref.watch(_authUserProvider).value?.metadata.lastSignInTime;
  if (lastSignInTime == null) return true;
  return lastSignInTime.isAfter(forceLogoutAfter);
});

/// 세션 무효화(강제 로그아웃 감지)를 이미 처리 중/처리했는지 표시하는 가드.
///
/// 두 군데에서 같이 쓴다: (1) 대시보드가 세션이 무효해진 걸 감지해 로컬 로그아웃 처리를
/// 시작할 때 true로 켜서 중복 처리를 막고, (2) "다른 모든 기기에서 로그아웃" 버튼을 누른
/// 바로 그 기기가 스스로를 선점적으로 true로 켜서, 본인이 의도적으로 누른 동작에 대해
/// "세션이 만료되었습니다" 같은 안내가 뜨지 않게 한다. 로그인하면 다시 false로 풀어서
/// 다음 세션에서도 감지할 수 있게 한다.
class SessionInvalidationHandledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final sessionInvalidationHandledProvider =
    NotifierProvider<SessionInvalidationHandledNotifier, bool>(
      SessionInvalidationHandledNotifier.new,
    );
