import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  // GoogleSignIn.instance.initialize()는 딱 한 번만 호출하고 그 완료를 기다린 뒤에
  // 다른 메서드를 써야 한다(패키지 문서 요구사항) — signInWithGoogle()을 여러 번
  // 호출해도 초기화가 한 번만 실행되도록 플래그로 가드한다.
  bool _googleSignInInitialized = false;

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

  /// [email] 문서의 `androidAccessEnabled`(boolean)가 true인지 실시간으로 흘려보낸다 —
  /// 관리자가 이 사용자에게 안드로이드 접근 자체를 열어줬는지를 나타내는 필드다. 계정
  /// 다이얼로그가 "Google 계정 연동" 버튼을 보여줄지 판단하는 용도 — 관리자가 아직 true로
  /// 안 켠 사용자에게는 버튼을 안 보여줘서, 허용 안 된 사용자가 임의로 연동을 시도하는
  /// 걸 막는다.
  Stream<bool> watchAndroidAccessEnabled(String email) {
    return _firestore
        .collection('admin_allowed_emails')
        .doc(email.toLowerCase())
        .snapshots()
        .map((doc) => doc.data()?['androidAccessEnabled'] == true);
  }

  /// [email]의 admin_allowed_emails 문서에서 forceLogoutAfter를 실시간으로 흘려보낸다
  /// (없으면 null). "다른 모든 기기에서 로그아웃"을 감지해 다른 탭/기기를 즉시 로그아웃
  /// 시키는 용도 — 실제 권한 검증은 Firestore/Storage 규칙이 같은 필드로 다시 확인하므로,
  /// 여기서 조금 늦거나 틀려도 보안에는 영향이 없다(체감 속도만 개선하는 보조 수단).
  ///
  /// 콜드 스타트 시 이미 무효한 세션으로 todo/memo/files 리스너가 동시에 거부당하면, 같은
  /// 커넥션을 공유하는 .snapshots() 구독도 덩달아 지연될 수 있다 — 그래서 1회성 get()으로
  /// 먼저 값을 확인해 최대한 빨리 흘려보낸 뒤, 이어서 실시간 구독으로 넘어간다.
  Stream<DateTime?> watchForceLogoutAfter(String email) async* {
    final docRef = _firestore.collection('admin_allowed_emails').doc(email.toLowerCase());
    try {
      yield _parseForceLogoutAfter(await docRef.get());
    } catch (_) {
      // 실패해도 무시 — 바로 아래 실시간 구독이 이어서 값을 채워준다.
    }
    yield* docRef.snapshots().map(_parseForceLogoutAfter);
  }

  DateTime? _parseForceLogoutAfter(DocumentSnapshot<Map<String, dynamic>> doc) =>
      (doc.data()?['forceLogoutAfter'] as Timestamp?)?.toDate();

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

  /// 안드로이드 전용 로그인 경로: Google 계정으로 로그인한다. 이 기기의 Google 계정이
  /// 웹에서 [linkGoogleAccount]로 이미 회사메일 계정에 연동돼 있으면 같은 uid로
  /// 로그인되어 할일/메모(`users/{uid}/...`)를 그대로 이어서 본다. 아직 연동 전이면
  /// 완전히 새로운 별도 계정이 생성되고, 그 Google 계정 이메일이 화이트리스트에 없는 한
  /// 아래 [_ensureApproved]에서 곧바로 막힌다.
  Future<void> signInWithGoogle() async {
    if (!_googleSignInInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleSignInInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    await _auth.signInWithCredential(credential);
    // 미승인이면 로컬 세션만 끊는 게 아니라 방금 막 생성된 계정 자체를 지운다(아래
    // _ensureApproved 참고) — 그냥 signOut만 하면 화이트리스트에 없는 Google 계정으로
    // 서버에 빈 계정만 남아, 나중에 그 계정을 웹에서 연동하려 할 때
    // credential-already-in-use로 막히는 문제가 있었다.
    await _ensureApproved(deleteIfUnapproved: true);
  }

  /// 웹 전용: 지금 로그인된 회사메일 계정에 Google 계정을 추가로 연동한다. 이후
  /// 안드로이드에서 그 Google 계정으로 [signInWithGoogle]을 호출하면 새 계정이 아니라
  /// 이 계정과 같은 uid로 로그인되어 데이터를 공유해서 본다. Firebase 표준 계정 연동
  /// 기능(`linkWithPopup`)이라 `google_sign_in` 패키지 없이도 동작한다.
  Future<void> linkGoogleAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    // prompt: select_account가 없으면 브라우저에 이미 로그인된 Google 계정이 하나뿐일 때
    // 계정 선택 화면 없이 곧장 그 계정으로 진행돼버린다 — 회사메일 계정과는 다른 별도
    // Google 계정을 골라 연동하려는 의도인 경우가 많아 항상 선택 화면을 띄우게 강제한다.
    final provider = GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'});
    await user.linkWithPopup(provider);
  }

  /// [linkGoogleAccount]로 걸어둔 연동을 해제한다. 이메일 링크 로그인은 그대로 남으므로
  /// 이 계정에 로그인할 수단이 없어지는 일은 없다. 해제 후 이 Google 계정으로 안드로이드에서
  /// 다시 로그인하면(signInWithGoogle) 더 이상 같은 uid로 연결되지 않고 완전히 새 계정이 된다.
  Future<void> unlinkGoogleAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.unlink(GoogleAuthProvider.PROVIDER_ID);
  }

  /// 지금 로그인된 계정에 Google 제공자가 이미 연동돼 있는지 — 계정 다이얼로그가
  /// "Google 계정 연동" 버튼을 보여줄지, 이미 연동됨을 보여줄지 판단하는 용도.
  bool get isGoogleAccountLinked =>
      _auth.currentUser?.providerData.any((info) => info.providerId == 'google.com') ?? false;

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

  /// [deleteIfUnapproved]가 true면 미승인일 때 로그아웃 대신 방금 막 로그인한 계정
  /// 자체를 삭제한다(막 로그인한 직후라 재인증 없이 삭제 가능) — signInWithGoogle처럼
  /// 계정이 그 순간 새로 생성될 수 있는 경로에서, 승인 안 된 채로 방치되는 빈 계정이
  /// 남지 않게 하는 용도. completeSignInIfLink(이메일 링크)는 이 문제가 없으므로
  /// 기본값(false, 로그아웃만)을 그대로 쓴다.
  Future<void> _ensureApproved({bool deleteIfUnapproved = false}) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (email == null) return;

    if (!await _isEmailApproved(email)) {
      if (deleteIfUnapproved) {
        try {
          await user!.delete();
        } catch (_) {
          await _auth.signOut();
        }
      } else {
        await _auth.signOut();
      }
      throw const NotApprovedException();
    }
  }
}
