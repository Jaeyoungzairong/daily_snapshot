import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (_) {
      throw ApiException('네트워크 연결에 실패했습니다.');
    }

    if (response.statusCode != 200) {
      throw ApiException('요청에 실패했습니다 (${response.statusCode}).');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
