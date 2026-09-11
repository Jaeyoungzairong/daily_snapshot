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
///
/// `admin_allowed_emails/{email}` 문서 필드:
/// - `isActive` (bool): 로그인 승인 여부
/// - `isAdmin` (bool): 공유 파일 삭제 등 관리자 전용 기능 허용 여부
/// - `forceLogoutAfter` (Timestamp, 선택): 이 시각 이후 발급된 세션(로그인)만 유효.
///   "다른 모든 기기에서 로그아웃" 기능이 갱신하며, Firestore/Storage 규칙이
///   `request.auth.token.auth_time`(그 세션이 실제 로그인한 시각)과 비교해 이보다
///   오래된 세션의 모든 요청을 거부한다 — 이미 발급된 토큰이 살아있어도(최대 1시간)
///   다음 요청부터 즉시 막히므로, 토큰 자체를 무효화하는 것보다 체감상 더 빠르다.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore, KeyValueStore? store})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance,
      _store = store ?? SharedPreferencesKeyValueStore();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final KeyValueStore _store;

  /// 로그인 상태가 바뀔 때마다 현재 사용자(로그인 안 됐으면 null)를 흘려보낸다. uid/email
  /// 등 파생 정보는 이 스트림 하나만 구독해서 만들어야 한다 — authStateChanges()는 일반
  /// 브로드캐스트 스트림이라 여러 곳에서 각자 새로 구독하면, 이미 지나간 "로그인 복원"
  /// 이벤트를 뒤늦게 구독한 쪽은 다시 받지 못해 영원히 대기하게 된다.
  Stream<User?> userChanges() => _auth.authStateChanges();

  /// [email]의 admin_allowed_emails 문서에 isAdmin:true가 있는지 실시간으로 흘려보낸다
  /// (공유 파일 삭제 등 관리자 전용 기능을 UI에서 보여줄지 판단하는 용도 — 실제 권한
  /// 검증은 Firestore/Storage 규칙에서 같은 필드를 다시 확인한다).
  Stream<bool> watchIsAdmin(String email) {
    return _firestore
        .collection('admin_allowed_emails')
        .doc(email.toLowerCase())
        .snapshots()
        .map((doc) => doc.data()?['isAdmin'] == true);
  }

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
  ///
  /// 이 브라우저에 저장된 이메일이 없으면(다른 기기에서 링크를 열었거나, 발송 한도를
  /// 우회하려고 관리자가 직접 생성한 링크를 열었을 때) [emailOverride]를 대신 사용한다.
  Future<void> completeSignInIfLink(String link, {String? emailOverride}) async {
    if (!isSignInLink(link)) return;

    final stored = await _store.getString(_pendingEmailKey);
    await _store.remove(_pendingEmailKey);
    final email = stored ?? emailOverride?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      throw const PendingEmailNotFoundException();
    }

    await _auth.signInWithEmailLink(email: email, emailLink: link);
    await _ensureApproved();
  }

  Future<void> signOut() => _auth.signOut();

  /// 이 계정으로 로그인된 모든 기기(이 기기 포함)의 세션을 무효화한다.
  ///
  /// `auth_time`(실제 로그인 시각)은 토큰이 자동 갱신되어도 바뀌지 않아서, 특정 기기만
  /// 콕 집어 구분할 방법이 Firebase Auth 표준 클레임만으로는 없다. 그래서 "이 기기는
  /// 남기고 나머지만" 대신 전부 로그아웃시키는 것으로 설계했다 — 이 기기도 다음 요청부터
  /// 막히므로, 곧바로 로컬 세션도 정리해서 "로그인된 것처럼 보이는데 아무 것도 안 되는"
  /// 상태가 되지 않게 한다.
  Future<void> forceLogoutAllDevices() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;
    await _firestore.collection('admin_allowed_emails').doc(email.toLowerCase()).set({
      'forceLogoutAfter': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _auth.signOut();
  }

  Future<void> _ensureApproved() async {
    final email = _auth.currentUser?.email;
    if (email == null) return;

    if (!await _isEmailApproved(email)) {
      await _auth.signOut();
      throw const NotApprovedException();
    }
  }
}
