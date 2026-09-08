/// 공유 파일함에 올라온 파일 하나의 메타데이터. 실제 파일 바이트는 Storage([storagePath])에
/// 있고, 이 문서는 목록 표시·다운로드 URL 조회에 필요한 정보만 담는다.
class FileEntry {
  const FileEntry({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.contentType,
    required this.storagePath,
    required this.uploadedByEmail,
    required this.uploadedAt,
  });

  final String id;
  final String name;
  final int sizeBytes;
  final String contentType;
  final String storagePath;
  final String uploadedByEmail;
  final DateTime uploadedAt;

  factory FileEntry.fromJson(String id, Map<String, dynamic> json) {
    return FileEntry(
      id: id,
      name: json['name'] as String,
      sizeBytes: json['sizeBytes'] as int,
      contentType: json['contentType'] as String,
      storagePath: json['storagePath'] as String,
      uploadedByEmail: json['uploadedByEmail'] as String,
      uploadedAt: DateTime.parse(json['uploadedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sizeBytes': sizeBytes,
      'contentType': contentType,
      'storagePath': storagePath,
      'uploadedByEmail': uploadedByEmail,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }
}
