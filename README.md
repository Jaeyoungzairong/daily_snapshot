# Daily Snapshot

매일 아침 확인하는 날씨 · 환율 · 오늘 할일 · 공유 파일 · 자주 가는 사이트를 한 화면에 모아
보여주는 Flutter Web 대시보드입니다. 정적 사이트로 빌드되어 Firebase Hosting에 배포되고,
로그인·데이터 동기화·파일 저장은 Firebase(Auth/Firestore/Storage)를 사용합니다.

## 주요 기능

### 날씨
- 기상청 단기예보 API(`VilageFcstInfoService_2.0`)의 초단기실황(`getUltraSrtNcst`) + 단기예보(`getVilageFcst`)를 조합해
  현재 기온/하늘상태와 시간별 예보를 표시
- 강수확률(POP), 강수량(PCP/RN1) 표시
- 도시 검색 시 번들된 기상청 격자 지역 목록(`assets/kma_regions.json`)에서 좌표를 찾아 기상청 격자(nx, ny)로 변환
- 검색창의 "내 위치로 찾기" 버튼으로 브라우저 위치를 조회해 가장 가까운 기상청 지점을 자동 선택
  (한반도에서 100km 넘게 벗어난 좌표는 지원하지 않음)
- 마지막으로 선택한 도시를 저장해 다음 방문 시 자동으로 불러옴

### 환율
- [open.er-api.com](https://open.er-api.com)에서 실시간 환율 시세 조회
- [frankfurter.dev](https://api.frankfurter.dev)에서 기간별 환율 히스토리 조회 후 차트로 표시(`fl_chart`)
- 통화 선택은 목록에서 고르기만 가능(텍스트 입력/키보드 비활성화)
- 간단 환산 입력창은 숫자/소수점만 남도록 처리하되, 한글 IME 조합 중에는 손대지 않아
  조합 중 기존 입력값이 사라지는 문제를 방지

### 로그인 / 계정
- 화면 우측 상단 계정 아이콘에서 로그인·로그아웃을 한 곳에서 처리(특정 카드에 종속되지 않고
  전역에서 접근 가능)
- Firebase 이메일 링크(비밀번호 없는) 로그인. 관리자가 Firestore에 등록·활성화한 이메일만
  로그인할 수 있고, 미승인 이메일은 로그인 링크 발송 자체를 하지 않음(발송 한도 절약,
  "링크가 안 왔나?" 하는 혼란 방지)
- 메일 링크를 클릭해 앱으로 돌아오면 계정 다이얼로그가 자동으로 열리고, 그 안에서 "로그인
  계속하기"를 직접 눌러야 로그인이 완료됨 — 메일 보안 스캐너가 링크를 미리 열어봐도 1회용
  로그인 코드가 그 자리에서 소모되지 않도록 하기 위함
- 로그인해야 이용 가능한 기능: 오늘 할일/메모, 공유 파일함

### 오늘 할일 / 메모
- 체크리스트(완료 항목은 취소선만 표시하고 목록 순서는 그대로 유지 — 완료했다고 아래로 밀리지
  않음), 항목 삭제와 완료 항목 일괄 삭제 시 확인 다이얼로그로 실수 방지
- 메모는 제목을 붙여 여러 개를 만들어 관리(칩 형태 선택기), 좌우 버튼으로 순서 변경 가능, 삭제 시 확인 다이얼로그
- 이메일 링크 로그인 후 이용 가능(로그인 방법은 위 "로그인 / 계정" 참고)
- 데이터는 Firestore에 저장되어 기기 간 동기화됨(같은 계정으로 로그인하면 어디서든 동일한 목록을 봄).
  트랜잭션으로 갱신해 여러 기기에서 거의 동시에 수정해도 나중 쓰기가 앞선 변경을 덮어쓰지 않음
  (낙관적 로컬 갱신 + 실시간 스트림 반영)
- 항목별 생성/완료 시각을 함께 저장해 추후 날짜별 기록 조회 기능 확장을 고려한 데이터 구조
- 도시 선택/테마처럼 기기 하나에만 있으면 되는 값은 그대로 로컬(`shared_preferences`)에 저장 — 로그인이
  필요한 건 할일/메모뿐

### 바로가기
- 자주 쓰는 외부 사이트(그룹웨어, 사내 NAS, 지도, 메일, 검색 등)를 아이콘 목록으로 두고 클릭 시 새 탭으로 이동

### 공유 파일함
- Firebase Storage + Firestore로 파일을 올리고 받는 기능. 계정별 저장소가 아니라 승인된 모든
  사용자가 함께 쓰는 공유 풀(파일 하나당 최대 100MB, 전체 최대 30개)
- 이메일 링크 로그인 후 이용 가능(로그인 방법은 위 "로그인 / 계정" 참고). 업로드·다운로드·미리보기는
  승인된 사용자 누구나 가능하고, 삭제는 관리자(승인 명단의 `isAdmin: true`)는 전체 파일을, 일반
  사용자는 본인이 올린 파일만 가능
- 확장자별로 미리보기 가능 여부를 판단해 pdf/이미지/텍스트/mp4/mp3는 "미리보기"(새 탭에서 열기)와
  "다운로드"(실제 저장)를 아이콘으로 구분 제공. 다운로드는 Storage 버킷 CORS 설정 + 브라우저에서
  바이트를 직접 받아 Blob으로 저장하는 방식으로, 미리보기 가능한 형식도 정확히 파일로 저장됨
- 업로드·다운로드 모두 진행률을 표시(대용량 파일에서도 버튼이 응답 없어 보이지 않도록)
- 여러 파일을 한 번에 선택해 업로드 가능, 일부만 실패해도 나머지는 계속 진행. 이미 같은 이름의
  파일이 있으면 업로드 전에 확인(취소/중복 제외/그대로 진행 중 선택)
- 최신 업로드 순 정렬, 현재 개수(n/30)를 상시 표시

### 화면 테마
- 앱바 아이콘으로 다크/라이트 테마 전환, 마지막으로 선택한 테마를 저장해 다음 방문 시 그대로 적용
- 전체 글꼴을 Pretendard(Regular/SemiBold)로 번들링해 플랫폼(기기별 시스템 한글 폰트)에
  관계없이 항상 동일하게 보이도록 통일

## 기술 스택
- Flutter Web (다른 플랫폼 타깃 없음)
- 상태 관리: `flutter_riverpod` (`AsyncNotifier`/`StreamNotifier`/`Notifier` 기반)
- 인증/데이터베이스: `firebase_auth`(이메일 링크 로그인) + `cloud_firestore`(할일/메모/공유 파일함 메타데이터
  동기화). 보안 규칙에서 로그인 승인 명단(`admin_allowed_emails`)을 함께 검증 — 단건 조회(`get`)는 누구나
  가능하게 열어 로그인 전에도 승인 여부를 미리 확인할 수 있게 하고, 목록 조회(`list`)는 막아 전체
  승인자 목록이 노출되지 않게 함. 같은 문서의 `isAdmin` 필드로 파일 삭제 등 관리자 전용 동작을 구분
- 파일 저장: `firebase_storage`(공유 파일함 실 파일 저장) + `file_picker`(파일 선택)
- 로컬 저장소: `shared_preferences` (공통 `KeyValueStore` 추상화로 감싸 테스트에서 인메모리로 대체)
- 차트: `fl_chart`
- HTTP: `http` (환율/날씨 API 호출 + 공유 파일함 다운로드 스트리밍)
- 글꼴: [Pretendard](https://github.com/orioncactus/pretendard) (Regular/SemiBold, `assets/fonts/`에 번들링, OFL 라이선스)

## 프로젝트 구조
```
lib/
  core/            테마, 공용 위젯, 로컬 저장소(KeyValueStore)·HTTP 클라이언트(ApiClient)·설정(LocalConfig)·
                   인증(AuthService/AuthProvider, 로그인 폼과 AppBar 계정 다이얼로그까지 포함) 등 공통 요소
  features/
    weather/       날씨 (기상청 API 연동, 지역 검색, 내 위치로 찾기)
    exchange_rate/ 환율 (실시간 시세 + 히스토리 차트)
    todo/          오늘 할일 / 다중 메모 (로그인 필요, Firestore 동기화)
    files/         공유 파일함 (Storage 업로드/다운로드/미리보기, 로그인 필요, 삭제는 관리자 전체·
                   일반 사용자는 본인 업로드분만)
    shortcuts/     바로가기 링크
    dashboard/     위 카드들을 배치하고 AppBar(테마 전환, 계정 다이얼로그 진입점)를 구성하는 페이지
```

## 로컬 개발

### 1. 의존성 설치
```bash
flutter pub get
```

### 2. API 키 설정
기상청 API를 쓰려면 서비스 키가 필요합니다. `lib/core/config/secrets.example.json`을 참고해
같은 위치에 `secrets.json`(gitignore됨, 커밋되지 않음)을 만들고 실제 키를 넣습니다.

```json
{
  "KMA_SERVICE_KEY": "YOUR_KMA_SERVICE_KEY_HERE"
}
```

### 3. 실행
```bash
flutter run -d chrome --dart-define-from-file=lib/core/config/secrets.json
```

> `flutter run -d chrome`은 매 실행마다 임시 브라우저 프로필을 새로 띄우므로, 세션이 끝나면
> `localStorage`(도시/테마 선택값, 로그인 세션)가 초기화됩니다. 데이터가 계속 유지되는 상태로
> 확인하려면 아래처럼 빌드 후 고정 포트로 정적 서빙하는 방법을 씁니다.

> 할일/메모는 Firebase 이메일 링크 로그인이 필요하고, 그중에서도 Firestore의
> `admin_allowed_emails` 컬렉션에 등록·활성화(`isActive: true`)된 이메일만 로그인할 수
> 있습니다. 로컬에서 이 기능까지 테스트하려면 별도 Firebase 프로젝트를 만들고
> `lib/firebase_options.dart`를 그 프로젝트 설정으로 교체한 뒤, `firestore.rules`를 배포하고
> 본인 이메일을 승인 명단에 추가해야 합니다.

> 공유 파일함까지 테스트하려면 위 설정에 더해 `storage.rules`도 배포하고, Storage 버킷 설정에서
> CORS(허용 origin에 로컬 서빙 주소 포함, `GET`, 응답 헤더 `Content-Type`/`Content-Length`)를
> 켜야 다운로드 진행률·강제 저장이 동작합니다. 파일 삭제까지 테스트하려면 승인 명단 문서에
> `isAdmin: true`도 추가합니다.

```bash
flutter build web --dart-define-from-file=lib/core/config/secrets.json
dhttpd --path build/web --port 8766
```
그 후 브라우저에서 `http://localhost:8766`으로 접속하면 됩니다(같은 고정 주소를 계속 쓰므로
브라우저의 일반 프로필에 데이터가 유지됩니다). 코드를 수정하면 `flutter build web`을 다시
실행해야 반영됩니다.

> 화면 우측 하단의 버전 표시는 배포 워크플로가 주입하는 값이라 로컬 빌드에서는 기본값인
> `v0.0.0+1`로 보입니다. 정상입니다.

### 정적 분석 / 테스트
```bash
flutter analyze
flutter test
```

## 배포
`main` 브랜치에 push되면 `.github/workflows/deploy-firebase.yml`이 Firebase Hosting
(`daily-snapshot-3ff12.web.app`)에 자동 배포합니다. 이전에 쓰던
`.github/workflows/deploy.yml`(GitHub Pages)은 Firebase Hosting 안정성을 지켜보는 동안
수동 실행(`workflow_dispatch`)으로만 남겨뒀고, 문제가 생기면 트리거를 다시 되돌려 즉시
롤백할 수 있습니다. 두 워크플로 모두 빌드 단계는 `.github/actions/build-web` 컴포짓
액션을 공유합니다. `KMA_SERVICE_KEY`는 저장소 Settings > Secrets에 등록된 값을 빌드 시
`--dart-define`으로 주입합니다.

Firebase Hosting 설정(`firebase.json`)은 SPA 라우팅을 위한 rewrite와, 해시가 붙는 정적
자산은 영구 캐시하되 `index.html`/서비스워커는 매번 새로 받도록 캐시 헤더를 구분해뒀습니다.

### 버전 관리
`pubspec.yaml`의 `version`은 `dev` 브랜치를 `main`에 병합할 때마다 그날 날짜 기준
`YY.M.D+빌드번호`(예: `26.8.31+1`) 형식으로 갱신합니다. 같은 날 다시 배포하면 빌드번호만
올립니다. 이 값은 빌드 시 `APP_VERSION`으로 주입되어 화면 우측 하단에 표시됩니다. 병합 후
GitHub의 Releases 기능으로 같은 버전(`v26.8.31`)의 태그를 남기며, 별도 CHANGELOG 파일은
두지 않고 커밋 메시지/릴리스 노트로 대신합니다.

## 향후 고려 중인 기능
- 기상청 중기예보(3~10일) 연동 — 현재 사용 중인 서비스 키가 `MidFcstInfoService`에 등록되어 있지
  않아 보류 중
- 오늘 할일의 이전 기록을 날짜별로 조회하는 기능
- 공유 파일함(업로드 상한, 중복 파일명 처리, 다운로드 진행률 등)에 대한 자동화 테스트 추가
- GitHub Pages 배포 경로 완전 정리 — Firebase Hosting 안정성이 충분히 확인되면 제거
- 관리자(나)만 접근 가능한 개인 파일함 — 공유 파일함과 별도 풀로 검토 중
