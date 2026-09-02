import 'package:firebase_auth/firebase_auth.dart';

/// Firebase 인증을 감싼다. 할 일/메모(Firestore)는 구글 로그인 뒤에만 쓸 수 있고,
/// 로그인 전에는 아예 관련 기능을 노출하지 않는다(익명 로그인은 쓰지 않음).
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// 로그인 상태가 바뀔 때마다 현재 uid(로그인 안 됐으면 null)를 흘려보낸다.
  Stream<String?> uidChanges() => _auth.authStateChanges().map((user) => user?.uid);

  Future<void> signInWithGoogle() => _auth.signInWithPopup(GoogleAuthProvider());
}
