import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// 외부 API를 부르는 FutureProvider에 넘기는 재시도 정책.
///
/// Riverpod 3의 기본 정책은 Exception으로 실패하면 최대 10번(대기 합계 약 38초) 다시 실행하고,
/// 그동안 상태를 로딩으로 둬서 카드에 스피너만 보이고 "다시 시도" 버튼도 나오지 않는다. 응답 없는
/// 서버(ApiClient 타임아웃 15초)라면 3분 넘게 스피너만 돈다. [ApiException]은 ApiClient가 이미
/// 원인(네트워크 실패, 응답 없음, 응답 형식 오류, API가 알려준 오류 코드)을 판별해 사용자에게
/// 보여줄 문구로 바꾼 오류라, 자동으로 재시도하지 않고 바로 에러 화면(다시 시도 버튼)을 보여준다.
/// 그 밖의 예외는 Riverpod 기본 정책을 그대로 따른다.
Duration? retryUnlessApiException(int retryCount, Object error) {
  if (error is ApiException) return null;
  return ProviderContainer.defaultRetry(retryCount, error);
}
