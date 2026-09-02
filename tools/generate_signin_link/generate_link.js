// 관리자 전용 비상 로그인 도구.
//
// Firebase Auth의 이메일 발송 한도(기본 5건/일)가 소진돼 앱에서 로그인 링크를
// 받을 수 없을 때, 이메일 발송 없이 로그인 링크 문자열만 직접 생성한다.
// (generateSignInWithEmailLink는 메일을 보내지 않으므로 그 한도에 걸리지 않는다.)
//
// 사용법:
//   1) Firebase Console > 프로젝트 설정 > 서비스 계정 > "새 비공개 키 생성"으로
//      받은 JSON을 이 폴더에 serviceAccountKey.json 이름으로 저장한다.
//      (이 파일은 프로젝트 전체에 대한 관리자 권한을 가지므로 절대 커밋하지 않는다 — .gitignore 처리됨)
//   2) 이 폴더에서 `npm install` 1회 실행.
//   3) `node generate_link.js <로그인할 이메일>` 실행 → 출력된 URL을 복사해서
//      브라우저 주소창에 붙여넣는다. 앱이 "로그인 요청 정보를 찾을 수 없다"며
//      이메일 입력을 요구하면 같은 이메일을 입력하고 "로그인 계속하기"를 누르면 된다.

const admin = require('firebase-admin');
const path = require('path');

// GitHub Pages 배포 주소. 저장소 이름이 바뀌거나 커스텀 도메인을 쓰게 되면 함께 수정할 것.
const APP_URL = 'https://jaeyoungzairong.github.io/daily_snapshot/';

const email = process.argv[2];
if (!email) {
  console.error('사용법: node generate_link.js <이메일>');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(path.join(__dirname, 'serviceAccountKey.json'))),
});

admin
  .auth()
  .generateSignInWithEmailLink(email.trim().toLowerCase(), {
    url: APP_URL,
    handleCodeInApp: true,
  })
  .then((link) => {
    console.log(link);
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
