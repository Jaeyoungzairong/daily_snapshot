# Daily Snapshot

매일 아침 확인하는 날씨 · 환율 · 오늘 할일 · 자주 가는 사이트를 한 화면에 모아 보여주는
Flutter Web 대시보드입니다. 백엔드 서버 없이 정적 사이트로 빌드되어 GitHub Pages에 배포됩니다.

## 주요 기능

### 날씨
- 기상청 단기예보 API(`VilageFcstInfoService_2.0`)의 초단기실황(`getUltraSrtNcst`) + 단기예보(`getVilageFcst`)를 조합해
  현재 기온/하늘상태와 시간별 예보를 표시
- 강수확률(POP), 강수량(PCP/RN1) 표시
- 도시 검색 시 번들된 기상청 격자 지역 목록(`assets/kma_regions.json`)에서 좌표를 찾아 기상청 격자(nx, ny)로 변환

### 환율
- [open.er-api.com](https://open.er-api.com)에서 실시간 환율 시세 조회
- [frankfurter.dev](https://api.frankfurter.dev)에서 기간별 환율 히스토리 조회 후 차트로 표시(`fl_chart`)

### 오늘 할일 / 메모
- 체크리스트(완료 항목은 취소선 유지, 자동 초기화 없이 계속 누적) + 자유 메모
- `shared_preferences`(웹에서는 브라우저 `localStorage`)로 로컬 저장
- 항목별 생성/완료 시각을 함께 저장해 추후 날짜별 기록 조회 기능 확장을 고려한 데이터 구조

### 바로가기
- 자주 쓰는 외부 사이트(그룹웨어, 사내 시스템, 지도, 메일 등)를 아이콘 목록으로 두고 클릭 시 새 탭으로 이동

## 기술 스택
- Flutter Web (다른 플랫폼 타깃 없음)
- 상태 관리: `flutter_riverpod` (`AsyncNotifier` 기반)
- 로컬 저장소: `shared_preferences`
- 차트: `fl_chart`
- HTTP: `http`

## 프로젝트 구조
```
lib/
  core/            테마, 위젯, 설정(LocalConfig) 등 공통 요소
  features/
    weather/       날씨 (기상청 API 연동, 지역 검색)
    exchange_rate/ 환율 (실시간 시세 + 히스토리 차트)
    todo/          오늘 할일 / 메모
    shortcuts/     바로가기 링크
    dashboard/     위 카드들을 배치하는 대시보드 페이지
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
> `localStorage`(할일/메모 데이터)가 초기화됩니다. 데이터가 계속 유지되는 상태로 확인하려면
> 아래처럼 빌드 후 고정 포트로 정적 서빙하는 방법을 씁니다.

```bash
flutter build web --dart-define-from-file=lib/core/config/secrets.json
dhttpd --path build/web --port 8766
```
그 후 브라우저에서 `http://localhost:8766`으로 접속하면 됩니다(같은 고정 주소를 계속 쓰므로
브라우저의 일반 프로필에 데이터가 유지됩니다). 코드를 수정하면 `flutter build web`을 다시
실행해야 반영됩니다.

### 정적 분석 / 테스트
```bash
flutter analyze
flutter test
```

## 배포
`main` 브랜치에 푸시되면 `.github/workflows/deploy.yml`이 `flutter build web`으로 빌드한 뒤
GitHub Pages에 배포합니다. `KMA_SERVICE_KEY`는 저장소 Settings > Secrets에 등록된 값을
빌드 시 `--dart-define`으로 주입합니다.

## 향후 고려 중인 기능
- 기상청 중기예보(3~10일) 연동 — 현재 사용 중인 서비스 키가 `MidFcstInfoService`에 등록되어 있지
  않아 보류 중
- 오늘 할일의 이전 기록을 날짜별로 조회하는 기능
