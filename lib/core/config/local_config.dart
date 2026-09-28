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
}
