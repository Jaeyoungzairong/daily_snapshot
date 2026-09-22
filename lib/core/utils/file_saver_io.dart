import 'dart:typed_data';

import 'package:file_saver/file_saver.dart' as file_saver;

/// 웹이 아닌 플랫폼(현재는 안드로이드)에서 파일을 기기에 저장한다. file_saver 패키지가
/// 안드로이드 스코프드 스토리지(Android 10+는 MediaStore, 그 이하는 file_saver가 자체
/// 병합하는 WRITE_EXTERNAL_STORAGE 권한)를 대신 처리해줘서, 이 앱에서 권한을 직접
/// 요청하거나 매니페스트에 추가할 필요가 없다.
Future<void> saveBytes(Uint8List bytes, {required String fileName, required String mimeType}) async {
  await file_saver.FileSaver.instance.saveFile(
    name: fileName,
    bytes: bytes,
    mimeType: file_saver.MimeType.custom,
    customMimeType: mimeType,
  );
}
