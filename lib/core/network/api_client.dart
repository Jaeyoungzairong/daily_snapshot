import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 외부 API 응답을 파싱하는 [parse] 안에서 응답 구조가 예상과 다를 때(필드 누락, 타입 불일치,
/// 날짜 형식 오류) 나는 TypeError/FormatException을 [ApiException]으로 바꿔 던진다 — 그대로
/// 두면 "Null check operator used on a null value" 같은 Dart 내부 메시지가 사용자 화면에
/// 그대로 노출된다. 이미 [ApiException]으로 던진 오류(예: API가 알려준 오류 코드)는 손대지 않고
/// 그대로 통과한다.
T parseApiResponse<T>(T Function() parse, {String message = '받아온 데이터의 형식이 올바르지 않습니다.'}) {
  try {
    return parse();
  } on TypeError {
    throw ApiException(message);
  } on FormatException {
    throw ApiException(message);
  }
}

class ApiClient {
  // timeout은 테스트에서 짧게 줄여 재정의할 수 있도록 공개 이름(_timeout과 다름)을 유지한다.
  ApiClient({http.Client? client, Duration timeout = const Duration(seconds: 15)})
    : _client = client ?? http.Client(),
      // ignore: prefer_initializing_formals
      _timeout = timeout;

  final http.Client _client;

  // 연결은 됐지만 응답이 오지 않는 경우(방화벽, 서버 무응답 등)를 대비한 타임아웃. 날씨/환율/
  // 도시 검색이 모두 이 클라이언트 하나를 공유하므로, 타임아웃이 없으면 그런 상황에서 해당
  // 카드가 재시도 버튼도 없이 무기한 로딩 상태로 멈춘다.
  final Duration _timeout;

  Future<Map<String, dynamic>> getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _send(uri);
    } on http.RequestAbortedException {
      throw ApiException('서버 응답이 없습니다. 잠시 후 다시 시도해주세요.');
    } catch (_) {
      throw ApiException('네트워크 연결에 실패했습니다.');
    }

    if (response.statusCode != 200) {
      throw ApiException('요청에 실패했습니다 (${response.statusCode}).');
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException('응답 형식이 올바르지 않습니다.');
    }
  }

  // 단순 Future.timeout은 시간이 지나도 실제 요청 자체는 계속 진행돼(연결이 새는 채로) 응답을
  // 기다린다 — http 패키지의 Abortable/AbortableRequest로 타임아웃 시 요청 자체를 실제로
  // 취소한다.
  Future<http.Response> _send(Uri uri) async {
    final abort = Completer<void>();
    final timer = Timer(_timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    try {
      final streamed = await _client.send(
        http.AbortableRequest('GET', uri, abortTrigger: abort.future),
      );
      return await http.Response.fromStream(streamed);
    } finally {
      timer.cancel();
    }
  }
}
