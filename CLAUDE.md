# 작업 규칙

- **임의로 패키지를 설치하거나 업데이트하지 말 것.** `pubspec.yaml`에 새 의존성을 추가하거나(`flutter pub add`), 기존 패키지를 올리는 작업(`flutter pub upgrade` 등)이 필요하면, 먼저 사용자에게 어떤 패키지를 왜 추가/업데이트하려는지 설명하고 승인을 받은 뒤 진행할 것.
- **`flutter analyze` / `flutter test`는 코드 수정 후 승인 없이 바로 실행해도 됨.** 실제 앱을 띄우지 않는 정적 분석/테스트라 비용이 낮음.
- **`flutter run` / `flutter build` 등으로 앱을 직접 실행하거나 브라우저로 눈으로 확인하는 작업은 임의로 하지 말 것.** 화면을 띄워서 스크린샷/DOM 확인 등으로 검증하고 싶다면, 먼저 사용자에게 물어보고 승인을 받은 뒤 진행할 것.
- **"검토", "분석", "제안", "추천" 또는 의문문(예: "~할 수 있는지", "~이 최선인지")으로 요청받았을 때는 임의로 코드를 수정하지 말 것.** 이런 요청은 실제 코드 수정이 아니라 의견/분석을 원하는 것이므로, 문제를 발견하거나 개선 아이디어가 떠올라도 그 자리에서 고치지 말고 발견한 내용과 제안하는 방향만 보고할 것. 실제 코드 수정은 사용자가 명시적으로 승인한 뒤에 진행할 것.
- **임의로 git commit 하지 말 것.** 코드 수정을 마쳤더라도 사용자가 명시적으로 "커밋해줘" 등으로 요청하기 전까지는 커밋하지 말 것.

# 프로젝트 배경

## 기술 스택 / 구현된 기능
Flutter Web + 안드로이드 대시보드(웹은 날씨·환율·할일·메모·공유파일함·바로가기 전체, 안드로이드는
할일·메모·공유파일함만). 상태관리는 `flutter_riverpod`, 백엔드는 Firebase(Auth/Firestore/Storage).
전체 기술 스택과 기능별 상세 설명은 README.md에 정리되어 있으니 여기서는 중복 서술하지 않음 —
새 세션은 먼저 README.md를 읽을 것.

## 프로젝트 구조 요약
```
lib/
  core/       테마, 공용 위젯, 인증(AuthService/AuthProvider, 이메일 링크+Google Sign-In), 로컬
              저장소, HTTP 클라이언트(network/: ApiClient·parseApiResponse·api_retry)
  features/
    weather/       날씨 (기상청 API, 지역 검색, 위치로 찾기) — 웹 전용
    exchange_rate/ 환율 (실시간 시세 + 히스토리 차트) — 웹 전용
    todo/          할일(TodoCard) / 메모(MemoCard) — 로그인 필요, Firestore 동기화, 웹/안드로이드 공통
    files/         공유 파일함 — 로그인 필요, 삭제는 관리자 전체·일반 사용자는 본인 업로드분만,
                   웹/안드로이드 공통(미리보기는 웹 전용)
    shortcuts/     바로가기 링크 — 웹 전용
    dashboard/     카드 배치 + AppBar(테마 전환, 계정 다이얼로그)
android/    안드로이드 네이티브 프로젝트(Gradle). google-services.json/key.properties는 gitignore됨
```
풀 버전(각 기능 상세 동작, 제약, 배포 방식 등)은 README.md에 있음 — 구조 파악이 더 필요하면
그때 읽을 것.

## 설계 결정과 이유
다시 물어볼 필요 없도록, 코드만 봐서는 바로 안 드러나는 선택의 이유를 정리한다.

- **로그인은 비밀번호 대신 이메일 링크 + 화이트리스트 승인제.** `admin_allowed_emails/{email}`
  문서의 `get`은 누구나 가능(로그인 전에도 승인 여부 확인용), `list`는 막아 전체 승인자 목록이
  노출되지 않게 함. 같은 문서의 `isAdmin`으로 관리자 전용 동작(파일 전체 삭제 등)을 구분.
- **할일/메모는 리스트 전체를 문서 하나로 트랜잭션 교체(`CloudListStore`), 공유 파일함은
  파일마다 문서 하나.** 할일/메모는 순서 변경·일괄 삭제 같은 복합 수정이 잦아 트랜잭션 통째
  교체가 일관성 보장에 유리함. 파일함은 그런 복합 수정이 없고(삭제만, 그것도 개별) Storage
  경로 관리에도 문서별 저장이 자연스러움.
- **세션 무효화 감지를 Firestore 규칙의 최종 거부에만 의존하지 않음.** Firestore SDK는
  permission-denied를 실제로 표면화하기 전에 자체 재시도/백오프를 거쳐서 체감 지연이 크다.
  그래서 `admin_allowed_emails/{email}`(항상 get 가능)을 클라이언트가 직접 구독해
  `forceLogoutAfter`를 더 빠르게 판단한다(`isSessionValidProvider`). 콜드 스타트 시 다른
  리스너들(할일/메모/파일함)이 동시에 거부당하면 같은 커넥션을 타는 이 구독도 지연될 수 있어,
  1회성 `get()`으로 먼저 값을 확인한 뒤 실시간 구독으로 넘어가도록 되어 있다
  (`AuthService.watchForceLogoutAfter`).
- **라이트모드 배경/카드 색을 M3 기본값 대신 커스텀 조합으로 바꿈.** 기본값(배경
  `surfaceContainerLowest` + 카드 `surfaceContainerLow`)은 라이트모드에서 거의 흰색-흰색이라
  카드 구분이 잘 안 보였다. 라이트는 배경에 옅은 톤을 주고 카드를 순백으로(`surfaceContainer`
  배경 + `surfaceContainerLowest` 카드), 다크는 원래 조합(배경 `surfaceContainerLowest` + 카드
  `surfaceContainerLow`)을 유지 — 다크는 이미 구분이 충분했음.
- **대시보드 카드마다 `GlobalKey`를 부여.** 900px 기준으로 넓은 화면(`Wrap`)↔좁은 화면
  (`Column`) 레이아웃이 전환되는데, 부모 위젯 타입 자체가 바뀌면 Flutter가 그 아래 전체를
  새로 마운트해서 카드별 로컬 상태(메모 선택, 페이지 번호 등)가 리사이즈 한 번에 날아간다.
  `GlobalKey`로 부모가 바뀌어도 같은 엘리먼트를 재사용하게 해서 방지.
- **메모 카드 전환 시 `cancelPendingEdits` 대신 `flushPending`을 씀.** 디바운스 저장 대기 중
  (500ms 안) 바로 다른 메모로 전환하면 입력한 내용이 저장 없이 사라지는 문제가 있었음 —
  전환 직전 무조건 먼저 저장(flush)하도록 바꿈.
- **공유 파일함 삭제는 Storage를 먼저 지우고, 성공했을 때만 Firestore 문서를 지움(반대로
  하면 목록에서는 사라졌는데 Storage에 파일이 남는 상황이 생김).** 다만 Storage는 지워졌는데
  Firestore 삭제만 실패하면 재시도 시 Storage 단계에서 "이미 없음(object-not-found)"으로
  막히던 문제가 있어, 그 에러는 "이미 지워진 상태"로 간주하고 통과시켜 재시도만으로 복구되게
  함(`FileRepository.deleteFile`).
- **안드로이드 로그인은 딥링크(App Links) 대신 Google Sign-In.** 처음엔 이메일 링크를
  안드로이드까지 그대로 확장하려고 App Links를 시도했지만, 사내 메일 앱이 링크를 가로채
  실제 기기에서 안정적으로 안 열리는 문제가 있어 롤백하고 Google Sign-In으로
  전환함(`AuthService.signInWithGoogle`).
- **웹에서 미리 연동한 Google 계정으로 안드로이드에서 로그인하면 같은 uid로 들어옴.**
  `AccountDialog`의 "Google 계정 연동하기"(`AuthService.linkGoogleAccount`, `linkWithPopup`)로
  지금 로그인된 회사메일 계정에 Google 제공자를 추가해두면, 이후 안드로이드에서 그 Google
  계정으로 `signInWithCredential`할 때 새 계정이 아니라 이미 연동된 그 uid로 로그인된다.
  연동해도 Firebase Auth의 최상위 `user.email`(승인 명단 조회 키)은 바뀌지 않고 원래
  회사메일로 남는다 — 그래서 연동 이후에도 `_isEmailApproved(user.email)` 검사가 그대로 유효함.
- **`admin_allowed_emails`에 `androidAccessEnabled`(bool) 필드를 추가해 계정 연동 버튼 노출을
  게이팅.** 관리자가 이 값을 true로 켜주지 않은 사용자에게는 계정 다이얼로그에 "Google 계정
  연동하기" 버튼 자체가 안 보인다(이미 연동된 계정은 예외로 계속 보여 해제 방법이 없어지지
  않게 함) — 승인 안 된 사용자가 임의로 연동을 시도하는 걸 막기 위함.
- **`signInWithGoogle()`은 미승인 시 로그아웃이 아니라 방금 생성된 계정을 삭제한다
  (`deleteIfUnapproved`).** `signInWithCredential`은 승인 여부와 무관하게 서버에 계정을 즉시
  만들어버려서, 단순 `signOut()`만 하면 승인 안 된 빈 계정이 서버에 계속 남는다. 이 방치된
  계정이 나중에 같은 Google 계정을 정상적으로 연동하려 할 때 `credential-already-in-use`로
  막는 실제 버그가 있었음 — 그래서 미승인이면 즉시 삭제한다.
- **앱 버전 표시는 dart-define 대신 `package_info_plus`로 통일.** 웹은 `flutter build web`이
  자동 생성하는 `build/web/version.json`을, 안드로이드는 설치된 APK의 네이티브 버전 정보를
  읽어와 `pubspec.yaml`의 `version`을 보여준다(빌드번호 `+N`은 사용자 화면에서 제외 — 같은 날
  재배포 구분용 내부 값이라, 2026-09-28 결정) — 플랫폼별로 값을 따로 주입할 필요가
  없어져 CI 빌드 스크립트도 단순해짐. 대시보드 하단에만 표시(계정 다이얼로그에 넣었다가 사용자 결정으로 다시 뺌, 2026-09-28).
- **할일/메모 낙관적 쓰기가 실패하면 "직전 화면 상태"가 아니라 스트림으로 마지막에 받은 서버
  값으로 롤백한다(`_OptimisticList._commit`).** 직전 화면 상태에는 아직 진행 중인 다른 쓰기의
  낙관적 반영분이 섞여 있어, 오프라인에서 두 변경이 겹쳐 둘 다 실패하면 저장 안 된 변경이 화면에
  남았다(서버는 그대로라 바로잡을 스냅샷도 안 옴). 서버 값 기준은 "다른 쓰기가 막 성공했는데 그
  스냅샷이 아직 안 온" 순간 잠깐 빠져 보이지만, 성공한 쓰기의 스냅샷이 곧 와서 항상 서버 상태로
  수렴한다. 한때 직전 상태 기준으로 바꿨다가 되돌린 이력이 있음 — 원인은 아래 테스트 가짜 저장소 항목.
- **메모 디바운스 자동저장이 실패해도 화면 값은 되돌리지 않는다.** 입력창에 사용자가 친 글이 남아
  있는데 상태만 옛 값이 되면 더 혼란스럽기 때문. 대신 대기 값(`_pendingTitle*`/`_pendingContent*`)을
  지우지 않고 남겨 `flushPending`(메모 전환·로그아웃·"다시 저장" 버튼)이 재시도하게 하고, 실패
  상태를 `memoUnsavedEditsProvider`(배너, 계정 바뀌면 자동 초기화)와 `memoSaveFailureProvider`
  (스낵바, 실패 상태로 바뀔 때 한 번만)로 알린다. `AccountDialog.onBeforeSignOut`은 모두 저장됐는지
  `bool`을 돌려주고, false면 "그래도 로그아웃" 확인을 받는다(core가 todo provider를 직접 모르게 콜백 유지).
- **이메일 링크 로그인 완료(`completeSignInIfLink`)는 승인 여부를 `signInWithEmailLink`보다 먼저
  확인하고, 저장된 요청 이메일은 로그인 성공 후에만 지운다.** 예전엔 먼저 지워서 일시적 오류 한 번에
  같은 링크로 재시도할 방법이 사라졌다. 실패는 `isTerminalSignInLinkError`로 분류해, 만료·저장된
  이메일로도 `invalid-action-code`·요청 이메일 없음만 "새 링크 필요"(URL 정리)로 보고 나머지(네트워크,
  미승인 — 아직 링크 미소모, 수동 입력 이메일의 `invalid-action-code` — 오타 가능성)는 링크 모드를 유지.
- **외부 API(날씨/환율)는 `ApiClient`에서 오류를 `ApiException`으로 통일하고, 그 provider들은
  `ApiException`을 자동 재시도하지 않는다(`retryUnlessApiException`).** Riverpod 3 기본 자동 재시도
  때문에 실패 시 로딩 스피너만 수십 초~수 분 보였다(아래 제약사항 참고). 타임아웃(15초)은
  `Future.timeout`이 아니라 `AbortableRequest`로 실제 요청을 취소하고, 응답 파싱 중 `TypeError`/
  `FormatException`은 `parseApiResponse`로 한국어 `ApiException`이 된다. 공유 파일함 다운로드는
  전체 시간 제한 대신 "30초간 청크가 안 오면" 끊는 정체 타임아웃(대용량 전송이 정상적으로 길 수 있음).
- **손상된 할일/메모 항목(필드 누락·타입 오류)은 읽을 때 건너뛰고, 쓸 때는 지우지 않고 문서 뒤에
  보존한다(`TodoRepository._watch`/`_mutate`).** 예전엔 한 항목만 깨져도 스트림 전체가 에러가 돼
  카드가 마비되고 "다시 시도"로도 복구가 안 됐다. 단 `items`가 배열이 아니거나 배열 안의 맵이 아닌
  값은 `CloudListStore._itemsOf`에서 걸러져 다음 쓰기 때 사라진다(수동 편집에서만 생기는 경우라 수용).
- **배포는 전부 Firebase 콘솔에서 수동(2026-09-28 결정).** 웹 Hosting만 `main` push 시 GitHub
  Actions로 자동 배포. 안드로이드 APK는 로컬 `flutter build apk` 후 App Distribution 콘솔에 업로드 —
  서명 키·`google-services.json`을 GitHub Secrets에 올리지 않기로 사용자가 명시적으로 결정했고,
  셀프 호스티드 러너도 채택하지 않음(자동 배포를 다시 제안하지 말 것). Firestore/Storage 규칙은 콘솔
  규칙 편집기에 파일 전체를 붙여넣어 게시 — 그래서 `firebase.json`에 `firestore` 키가 없는 게
  정상이다(추가했다가 사용자 결정으로 다시 지움, 다시 제안하지 말 것).
- **안드로이드 런처 아이콘은 `flutter_launcher_icons`로 웹 아이콘(`web/icons/Icon-512.png`,
  `Icon-maskable-512.png`)에서 생성한다.** 원본을 한 벌만 두려고 별도 이미지를 만들지 않았다.
  적응형 전경은 maskable 버전(글자 주변 여백 있음)을 쓰고 `adaptive_icon_foreground_inset: 0` —
  기본값 16%를 두면 여백이 이중으로 들어가 글자가 너무 작아진다. inset 0에서도 글자의 가장 먼
  픽셀이 중심에서 145px/512로 안전 영역(156px) 안이라 잘리지 않음(측정 확인). 배경색 `#0B5FA5`는
  아이콘 픽셀을 측정한 값. 생성물(`mipmap-*`, `drawable-*/ic_launcher_foreground.png`,
  `mipmap-anydpi-v26`, `values/colors.xml`)은 손으로 고치지 말고 다시 생성할 것.
- **`storage.rules`/`firestore.rules`의 `isAdmin` 접근은 `.get('isAdmin', false)`로 한다.** 같은
  파일의 `forceLogoutAfter`처럼, 관리자가 아닌 사용자 문서엔 필드 자체가 없을 수 있어 점(.) 표기로
  읽으면 규칙 평가 오류가 날 수 있기 때문(에뮬레이터 검증은 못 함 — Java 미설치).

## 알아낸 제약사항 / 주의할 점
- **`localhost:8766`은 `flutter run` 개발 서버가 아니라 `serve_static.bat`로 띄운 `build/web`
  정적 파일 서버.** 소스를 수정해도 자동 반영되지 않고, `flutter build web`을 다시 돌려야
  반영됨. 이 주소로 화면을 확인하기 전엔 `build/web/main.dart.js`가 최근 수정한 소스보다
  최신인지(타임스탬프) 확인하거나, 빌드 여부를 사용자에게 먼저 물어볼 것.
- **브라우저 도구의 리사이즈(`resize_window`)는 실제 창 리사이즈가 아니라 페이지 전체를
  다시 로드시킴.** "리사이즈해도 상태가 유지되는지" 같은 검증엔 이 도구를 못 쓴다(매번
  초기화된 것처럼 보임) — 이런 검증은 사용자에게 실제 브라우저 창을 직접 드래그해서
  확인해달라고 요청할 것.
- **Riverpod `ref.listen`은 리스너 등록 시점에 이미 있던 값엔 반응하지 않고, 이후 값이
  "바뀔 때"만 호출됨.** "데이터가 처음 도착했을 때 한 번만 실행" 같은 로직을 `ref.listen`으로
  짜면, provider가 이미 데이터를 가진 상태에서 그 위젯의 State가 새로 생기는 경우(리마운트)
  영영 실행 안 될 수 있다 — 이런 초기화 로직은 `build()`의 `data:` 분기 안에서 플래그로 직접
  체크할 것.
- **Flutter `Card` 위젯의 M3 기본 배경색은 `colorScheme.surface`가 아니라
  `surfaceContainerLow`.** 카드 색 관련 작업 전에 착각하지 않도록 주의.
- **Dart 3.7+ 포맷터는 trailing comma를 강제 줄바꿈 신호로 쓰지 않음**(과거 버전과 다름).
- **이메일 로그인 링크 완료 로직(`Uri.base` 기반)은 웹 전용으로 남겨두고, 안드로이드는 아예
  다른 로그인 수단(Google Sign-In)을 씀.** 처음엔 App Links로 안드로이드까지 이메일 링크를
  확장하려 했으나(딥링크 설계) 사내 메일 앱이 링크를 가로채는 문제로 롤백함 — 안드로이드
  로그인 관련 작업이 다시 필요해져도 딥링크 방향으로 가지 말 것(이미 시도하고 폐기함). 배경은
  위 "설계 결정과 이유"의 Google Sign-In 항목 참고.
- **안드로이드 release 빌드는 `android/app/src/debug/AndroidManifest.xml`의 권한을 상속받지
  않는다.** `flutter build apk`는 기본이 release라, `INTERNET` 같은 권한이
  `main/AndroidManifest.xml`에 없으면 배포용 APK에는 아예 빠진다 — `flutter run`(디버그
  매니페스트가 병합됨)으로는 절대 안 드러나서 실제로 놓쳤던 문제. 새 권한이 필요해지면 항상
  `main`에 추가할 것.
- **Google Workspace처럼 회사 이메일이 곧 Google 계정인 조직에서는, 웹에서 연동하지 않고
  안드로이드에서 바로 Google 로그인을 시도하면 `account-exists-with-different-credential`이
  날 수 있음.** 이미 이메일 링크로 만들어진 계정과 같은 이메일의 Google 자격증명으로
  `signInWithCredential`하면 발생 — `sign_in_prompt.dart`의 `describeAuthError()`에서 안내
  문구로 처리해둠.
- **Firestore 리스너는 권한이 거부되면 SDK 자체 재시도/백오프를 거친 뒤에야 에러가
  표면화됨.** 세션 무효화 등을 감지할 때 이 지연을 감안해야 함(위 "세션 무효화 감지" 항목
  참고).
- **`test/features/todo/todo_card_test.dart`와 `memo_card_test.dart`는 `_signedInOverrides()`/
  `_InMemoryCloudListStore` 같은 테스트 헬퍼를 각자 중복해서 갖고 있음.** 공유 파일로 뽑아
  import하지 않은 이유는 Dart의 `_` 프리픽스(프라이빗)가 클래스 단위가 아니라 **파일 단위**라,
  다른 파일에서 그대로 재사용할 수 없기 때문. 의도적인 중복이니 "왜 안 합쳤지" 하고 억지로
  공유 헬퍼 파일로 리팩터링하지 말 것(원하면 `_` 없이 공개 헬퍼로 승격하는 방법은 있음).
- **테스트의 `_InMemoryCloudListStore`는 파일마다 동작이 다르다.** `todo_provider_test.dart`의 것은
  실제 Firestore `snapshots()`처럼 구독 시 한 번 + 쓰기 성공마다 새 값을 다시 내보내고, 카드/저장소
  테스트의 것은 한 번만 내보낸다. 롤백·동기화처럼 "성공한 쓰기의 스냅샷이 나중에 도착하는" 동작을
  검증할 땐 반드시 다시 내보내는 쪽을 써야 한다 — 한 번만 내보내는 가짜로 검증했다가 잘못된 롤백
  설계(직전 상태 기준)를 맞다고 판단한 적이 있음.
- **Riverpod 3(3.4.x)은 provider가 `Exception`으로 실패하면 기본으로 최대 10번 자동 재시도하고
  (대기 200ms→6.4s, 합계 약 38초), 그동안 상태가 `AsyncLoading`이라 기본 `when`은 로딩 분기를
  탄다.** 즉 에러 화면/"다시 시도" 버튼이 한참 늦게 뜬다. `Error`(TypeError 등)는 재시도 안 함.
  새 외부 API provider를 만들면 `retry: retryUnlessApiException`을 지정할 것. 할일/메모/파일함
  Firestore 스트림 provider도 같은 재시도를 타는지는 확인 안 함(세션 무효화 감지 지연과 관련 가능).
- **Flutter 모바일 앱(안드로이드/iOS)은 입력창 바깥을 터치해도 포커스를 풀지 않는다**(웹과 마우스만
  해제 — SDK `_EditableTextTapOutsideAction`). 그래서 키보드가 계속 떠 있었다 — 안드로이드에 나오는
  입력창에는 `onTapOutside`로 포커스를 풀고, 대시보드 스크롤뷰는 `keyboardDismissBehavior: onDrag`.
  새 입력창을 추가하면 같은 처리를 할 것. 다른 입력창을 누르는 건 "바깥"이 아님(같은 TapRegion 그룹).
- **안드로이드는 targetSdk 36(Flutter 기본)이라 edge-to-edge가 강제돼 화면이 하단 네비게이션 바
  뒤까지 그려진다.** 대시보드는 스크롤 하단 패딩에 `MediaQuery.paddingOf(context).bottom`을 더해
  처리함. 화면 아래쪽에 붙는 UI를 새로 만들면 이 inset을 고려할 것.
- **`saveBytes`(file_saver.dart)는 웹/안드로이드 모두 `Future<void>`이고 반드시 await할 것.** 안드로이드
  구현은 실제 파일 I/O라, await 없이 호출했을 때 저장 실패가 아무 데도 전달되지 않았다.
- **`file_saver`가 끌어오는 `jni`/`jni_flutter`가 CMake와 Android SDK Platform 35를 요구한다.** 없는
  PC에서는 첫 release 빌드 때 Gradle이 자동 설치(오류 아님). Kotlin Gradle Plugin 경고
  (`file_saver`, `firebase_auth/core/storage`)는 지금은 빌드되지만 이후 Flutter에서 실패할 수 있음 —
  대응하려면 패키지 업그레이드(사전 승인 필요).
