// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

// file_saver_io.dart(안드로이드)의 saveFile()이 비동기라 시그니처를 맞춘다 — 호출부
// (file_provider.dart)가 플랫폼과 무관하게 항상 await할 수 있어야, 안드로이드에서 저장
// 실패(공간 부족 등)를 놓치지 않고 호출자에게 전달할 수 있다.
Future<void> saveBytes(Uint8List bytes, {required String fileName, required String mimeType}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = fileName
    ..click();
  html.Url.revokeObjectUrl(url);
}
