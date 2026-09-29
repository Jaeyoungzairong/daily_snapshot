{{flutter_js}}
{{flutter_build_config}}

// 캐시 탈출용 버전 쿼리. Flutter 웹 산출물(main.dart.js 등)은 파일명에 해시가 없는데, 예전
// firebase.json이 이런 파일에 1년 immutable 캐시를 걸어서 한 번 받은 브라우저는 배포 후에도
// 일반 새로고침으로 옛 코드를 계속 실행했다. 지금은 모든 파일이 no-cache(ETag 재검증)라 새
// 배포는 바로 반영되지만, 이미 immutable로 받아둔 브라우저는 같은 URL을 다시 묻지 않는다 —
// URL을 한 번 바꿔서 그 캐시를 빠져나오게 한다. index.html의 flutter_bootstrap.js?v=2와 같은
// 값이며, 배포할 때마다 올릴 필요는 없다(다시 immutable 캐시를 걸 때만 의미가 있다).
const cacheBustVersion = "2";
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath = `${build.mainJsPath}?v=${cacheBustVersion}`;
  }
}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/"
  }
});
