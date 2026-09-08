/// file_picker는 MIME 타입을 주지 않으므로, Storage에 올릴 때 확장자로 추정해서
/// 채워 넣는다 — 비워두면(application/octet-stream) 다운로드 시 브라우저가 미리보기 없이
/// 무조건 파일로만 저장하려 든다.
const Map<String, String> _mimeByExtension = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  // charset을 안 붙이면 브라우저가 새 탭에 열 때 한글 등 비ASCII 문자를 자기 locale
  // 기본 인코딩(대개 UTF-8이 아님)으로 잘못 해석해 깨져 보인다. readAsBytes()로 읽은
  // 원본 바이트를 그대로 올리므로, 파일 자체가 UTF-8로 저장돼 있어야 이 표시가 맞는다.
  'txt': 'text/plain; charset=utf-8',
  'csv': 'text/csv; charset=utf-8',
  'zip': 'application/zip',
  'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
};

String mimeTypeForExtension(String? extension) {
  return _mimeByExtension[extension?.toLowerCase()] ?? 'application/octet-stream';
}

/// 브라우저 새 탭에서 바로 열어 볼 수 있는(별도 프로그램 없이 렌더링되는) 형식인지.
/// "미리보기" 버튼을 보여줄지 판단하는 용도 — docx/xlsx/zip 등은 새 탭에서 못 열리므로
/// 제외한다.
const Set<String> _previewableExtensions = {
  'pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'txt', 'csv', 'mp4', 'mp3',
};

bool isPreviewableExtension(String? extension) {
  return _previewableExtensions.contains(extension?.toLowerCase());
}
