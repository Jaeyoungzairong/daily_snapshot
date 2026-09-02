import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/key_value_store.dart';

const String _pendingEmailKey = 'pending_signin_email';

/// 로그인 링크는 완료됐지만 이메일이 승인 명단(`admin_allowed_emails`)에 없거나
/// 비활성화(`isActive: false`) 상태일 때 던진다.
class NotApprovedException implements Exception {
  const NotApprovedException();
}

/// 로그인 링크를 요청했던 이메일을 이 브라우저에서 찾을 수 없을 때 던진다 —
/// 대개 링크를 요청한 기기/브라우저와 다른 곳에서 링크를 열었을 때 발생한다.
class PendingEmailNotFoundException implements Exception {
  const PendingEmailNotFoundException();
}

/// Firebase 인증을 감싼다. 할 일/메모(Firestore)는 이메일 링크 로그인 뒤에만 쓸 수 있고,
/// 그중에서도 관리자가 승인한 이메일만 실제로 데이터에 접근할 수 있다.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore, KeyValueStore? store})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance,
      _store = store ?? SharedPreferencesKeyValueStore();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final KeyValueStore _store;

  /// 로그인 상태가 바뀔 때마다 현재 uid(로그인 안 됐으면 null)를 흘려보낸다.
  Stream<String?> uidChanges() => _auth.authStateChanges().map((user) => user?.uid);

  bool isSignInLink(String link) => _auth.isSignInWithEmailLink(link);

  /// 로그인 링크를 요청했던 이메일을 지우지 않고 미리 확인만 한다(확인 화면에 보여주는 용도).
  Future<String?> peekPendingEmail() => _store.getString(_pendingEmailKey);

  /// [email]이 관리자 승인 명단(`admin_allowed_emails/{email}`)에 있고 활성화(`isActive: true`)
  /// 상태인지 확인한다. 문서를 단건 조회할 뿐 전체 명단은 조회하지 않는다(Firestore 규칙이
  /// 단건 조회만 허용하고 목록 조회는 막아두었기 때문). `isActive`를 따로 두는 이유는 관리자가
  /// 문서를 지웠다 새로 만들지 않고도 `false`로 바꿔서 접근을 잠깐 정지시켰다가 나중에
  /// 다시 `true`로 되돌릴 수 있게 하기 위함이다.
  Future<bool> _isEmailApproved(String email) async {
    final doc = await _firestore.collection('admin_allowed_emails').doc(email.toLowerCase()).get();
    return doc.exists && doc.data()?['isActive'] == true;
  }

  /// [email]로 로그인 링크를 발송하고, 링크 완료 시 확인할 수 있도록 이 브라우저에
  /// 이메일을 저장해 둔다. 승인 명단에 없는 이메일이면 발송하지 않고 예외를 던진다 —
  /// 그래야 사용자가 "링크가 안 왔나?" 헷갈리지 않고 바로 승인이 필요하다는 걸 알 수 있고,
  /// 발송 한도도 낭비하지 않는다.
  Future<void> sendSignInLink(String email) async {
    final normalizedEmail = email.toLowerCase();
    if (!await _isEmailApproved(normalizedEmail)) {
      throw const NotApprovedException();
    }
    await _auth.sendSignInLinkToEmail(
      email: normalizedEmail,
      actionCodeSettings: ActionCodeSettings(url: Uri.base.toString(), handleCodeInApp: true),
    );
    await _store.setString(_pendingEmailKey, normalizedEmail);
  }

  /// [link]가 로그인 링크라면 로그인을 완료하고 승인 여부까지 확인한다. 로그인 링크가
  /// 아니면 아무 일도 하지 않는다.
  Future<void> completeSignInIfLink(String link) async {
    if (!isSignInLink(link)) return;

    final email = await _store.getString(_pendingEmailKey);
    await _store.remove(_pendingEmailKey);
    if (email == null) {
      throw const PendingEmailNotFoundException();
    }

    await _auth.signInWithEmailLink(email: email, emailLink: link);
    await _ensureApproved();
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> _ensureApproved() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;

    if (!await _isEmailApproved(email)) {
      await _auth.signOut();
      throw const NotApprovedException();
    }
  }
}
