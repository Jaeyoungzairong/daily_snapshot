/// 확장자별 메타데이터. file_picker는 MIME 타입을 주지 않으므로 Storage에 올릴 때 확장자로
/// 추정해서 채워 넣고, 목록에서는 같은 표로 "미리보기" 버튼을 보여줄지 판단한다 — 하나의
/// 표로 묶어둬야 확장자 하나를 추가/수정할 때 두 군데를 따로 챙기지 않아도 된다.
class _FileTypeInfo {
  const _FileTypeInfo(this.mimeType, {this.previewable = false});

  final String mimeType;

  /// 브라우저 새 탭에서 바로 열어 볼 수 있는(별도 프로그램 없이 렌더링되는) 형식인지.
  /// docx/xlsx/zip 등은 새 탭에서 못 열리므로 false로 둔다.
  final bool previewable;
}

const Map<String, _FileTypeInfo> _fileTypes = {
  'pdf': _FileTypeInfo('application/pdf', previewable: true),
  'png': _FileTypeInfo('image/png', previewable: true),
  'jpg': _FileTypeInfo('image/jpeg', previewable: true),
  'jpeg': _FileTypeInfo('image/jpeg', previewable: true),
  'gif': _FileTypeInfo('image/gif', previewable: true),
  'webp': _FileTypeInfo('image/webp', previewable: true),
  // charset을 안 붙이면 브라우저가 새 탭에 열 때 한글 등 비ASCII 문자를 자기 locale
  // 기본 인코딩(대개 UTF-8이 아님)으로 잘못 해석해 깨져 보인다. readAsBytes()로 읽은
  // 원본 바이트를 그대로 올리므로, 파일 자체가 UTF-8로 저장돼 있어야 이 표시가 맞는다.
  'txt': _FileTypeInfo('text/plain; charset=utf-8', previewable: true),
  'csv': _FileTypeInfo('text/csv; charset=utf-8', previewable: true),
  'zip': _FileTypeInfo('application/zip'),
  'doc': _FileTypeInfo('application/msword'),
  'docx': _FileTypeInfo('application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  'xls': _FileTypeInfo('application/vnd.ms-excel'),
  'xlsx': _FileTypeInfo('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  'ppt': _FileTypeInfo('application/vnd.ms-powerpoint'),
  'pptx': _FileTypeInfo('application/vnd.openxmlformats-officedocument.presentationml.presentation'),
  'mp4': _FileTypeInfo('video/mp4', previewable: true),
  'mp3': _FileTypeInfo('audio/mpeg', previewable: true),
};

String mimeTypeForExtension(String? extension) {
  return _fileTypes[extension?.toLowerCase()]?.mimeType ?? 'application/octet-stream';
}

bool isPreviewableExtension(String? extension) {
  return _fileTypes[extension?.toLowerCase()]?.previewable ?? false;
}
