import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'file_entry.dart';

/// 공유 파일함을 Firestore(메타데이터)+Storage(실 파일)에 저장·조회한다.
///
/// todo/memo와 달리 파일마다 문서 하나(shared_files/{fileId})를 쓴다 — 삭제/순서변경 같은
/// 복합 수정이 없어(관리자 삭제만 있고, 그마저도 파일 하나 단위) [CloudListStore]처럼
/// "리스트 전체를 트랜잭션으로 통째 교체"하는 방식을 쓸 이유가 없기 때문이다.
class FileRepository {
  FileRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore.collection('shared_files');

  Stream<List<FileEntry>> watchFiles() {
    return _collection
        .orderBy('uploadedAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => FileEntry.fromJson(doc.id, doc.data())).toList());
  }

  /// 새 문서 ID를 미리 발급하고, 그 ID를 폴더처럼 쓰는 Storage 경로(shared_files/{문서ID}/
  /// {파일명})로 업로드 작업을 시작한다. 문서ID와 파일명을 밑줄로 붙이지 않고 경로를
  /// 나누는 이유는, 다운로드 시 브라우저가 URL의 마지막 경로 조각만으로 저장 파일명을
  /// 정하기 때문이다 — 밑줄로 붙이면 "문서ID_파일명" 전체가 파일명으로 보인다. 문서ID가
  /// 여전히 경로 앞부분에 있어서 같은 이름의 파일이 여러 개 올라와도 충돌하지 않는다.
  /// 진행률은 반환된 [UploadTask]의 snapshotEvents로 구독한다.
  ({String docId, String storagePath, UploadTask task}) startUpload({
    required String name,
    required Uint8List bytes,
    required String contentType,
  }) {
    final docId = _collection.doc().id;
    final storagePath = 'shared_files/$docId/$name';
    final task = _storage.ref(storagePath).putData(bytes, SettableMetadata(contentType: contentType));
    return (docId: docId, storagePath: storagePath, task: task);
  }

  Future<void> registerFile(FileEntry entry) => _collection.doc(entry.id).set(entry.toJson());

  Future<String> getDownloadUrl(String storagePath) => _storage.ref(storagePath).getDownloadURL();

  /// Storage 파일을 먼저 지우고, 성공했을 때만 Firestore 문서를 지운다. 순서를 바꾸면
  /// Storage 삭제가 실패했을 때 목록에서는 사라졌는데 Storage에는 파일이 남아 용량을
  /// 조용히 차지하는(눈에 안 보이는) 상황이 생긴다.
  Future<void> deleteFile(FileEntry entry) async {
    await _storage.ref(entry.storagePath).delete();
    await _collection.doc(entry.id).delete();
  }
}
