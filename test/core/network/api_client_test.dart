import 'dart:convert';

import 'package:daily_snapshot/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient.getJson', () {
    test('returns the decoded JSON body on a 200 response', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode({'ok': true}), 200),
      );
      final apiClient = ApiClient(client: client);

      final json = await apiClient.getJson(Uri.parse('https://example.com/data'));

      expect(json, {'ok': true});
    });

    test('throws ApiException with the status code on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('not found', 404));
      final apiClient = ApiClient(client: client);

      await expectLater(
        () => apiClient.getJson(Uri.parse('https://example.com/data')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('404'))),
      );
    });

    test('throws ApiException when the client itself fails (e.g. no connection)', () async {
      final client = MockClient((request) async => throw const SocketExceptionStub());
      final apiClient = ApiClient(client: client);

      await expectLater(
        () => apiClient.getJson(Uri.parse('https://example.com/data')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('네트워크'))),
      );
    });

    test('throws ApiException when the response body is not valid JSON', () async {
      final client = MockClient((request) async => http.Response('<html>not json</html>', 200));
      final apiClient = ApiClient(client: client);

      await expectLater(
        () => apiClient.getJson(Uri.parse('https://example.com/data')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('응답 형식'))),
      );
    });

    test('aborts and throws ApiException when the server never responds in time', () async {
      // AbortableRequest 정보는 MockClient.streaming 핸들러에만 원본 그대로 전달된다(일반
      // MockClient는 내부적으로 새 Request를 만들어 abortTrigger가 사라진다) — 실제 클라이언트가
      // 응답 없는 서버에 물려 있는 상황을, "타임아웃(abortTrigger)이 완료될 때까지 응답하지
      // 않다가 RequestAbortedException을 던지는" 핸들러로 재현한다.
      final client = MockClient.streaming((request, bodyStream) async {
        final trigger = (request as http.Abortable).abortTrigger;
        expect(trigger, isNotNull, reason: 'ApiClient는 항상 abortTrigger를 걸어야 한다');
        await trigger;
        throw http.RequestAbortedException(request.url);
      });
      final apiClient = ApiClient(client: client, timeout: const Duration(milliseconds: 30));

      await expectLater(
        () => apiClient.getJson(Uri.parse('https://example.com/data')),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('응답이 없습니다'))),
      );
    });
  });
}

/// http.Client가 던지는 실제 연결 실패 예외(SocketException 등 dart:io 전용 타입)를 대신할
/// 가벼운 테스트용 예외. 종류와 무관하게 ApiClient가 일괄적으로 '네트워크 연결에 실패했습니다'로
/// 변환하는지만 확인하면 되므로 굳이 dart:io를 끌어올 필요가 없다.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
