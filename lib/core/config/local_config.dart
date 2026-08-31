/// 이 파일에는 실제 키 값을 절대 넣지 않는다(커밋되는 파일이라 공개 저장소에 그대로 노출됨).
/// 값은 빌드/실행 시 --dart-define(-from-file)로 주입한다.
///
/// 로컬 개발: lib/core/config/secrets.json(gitignore됨, secrets.example.json 참고)을 만들고
///   flutter run --dart-define-from-file=lib/core/config/secrets.json
/// CI(GitHub Actions): 저장소 Settings > Secrets에 등록한 값을
///   --dart-define=KMA_SERVICE_KEY=${{ secrets.KMA_SERVICE_KEY }} 로 전달 (.github/workflows/deploy.yml 참고)
class LocalConfig {
  LocalConfig._();

  static const String kmaServiceKey = String.fromEnvironment('KMA_SERVICE_KEY');

  /// 배포 워크플로(deploy.yml)가 pubspec.yaml의 version을 읽어 빌드 시점에 주입한다.
  /// 로컬 실행처럼 주입되지 않은 경우 'dev'로 표시해 배포판과 구분한다.
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0+1');
}
