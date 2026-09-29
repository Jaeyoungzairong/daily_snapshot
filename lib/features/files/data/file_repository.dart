import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import 'file_entry.dart';

/// Firestore 문서들을 [FileEntry]로 바꾸되, 필드가 빠졌거나 타입이 다른 문서는 건너뛴다.
///
/// 공유 파일함은 모든 사용자가 같은 컬렉션을 보므로, 예전엔 문서 하나만 깨져도(콘솔 수동 편집
/// 실수, 규칙이 필드를 검증하지 않아 들어온 잘못된 문서 등) 스트림 전체가 에러가 돼 **모든
/// 사용자의** 파일함이 에러 화면으로 바뀌었다. 할일/메모(TodoRepository._watch)와 같은 방식으로
/// 읽을 수 있는 문서만 보여준다 — 건너뛴 문서는 지우지 않으므로 콘솔에서 고치면 다시 나타난다.
List<FileEntry> readableFileEntries(Iterable<(String id, Map<String, dynamic> data)> docs) {
  final entries = <FileEntry>[];
  for (final (id, data) in docs) {
    try {
      entries.add(FileEntry.fromJson(id, data));
    } catch (_) {}
  }
  return entries;
}

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

  // 150MB까지 오래 걸리는 전송이라 요청 전체에 하나의 시간 제한을 둘 수는 없다 — 대신 응답
  // 헤더를 기다리는 동안과, 전송 중 다음 청크가 이 시간 안에 오지 않으면(정체) 끊는다.
  // 정상적으로 데이터가 계속 오는 한(청크마다 타이머가 갱신됨) 파일 크기와 무관하게 끊기지
  // 않는다.
  static const Duration _stallTimeout = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('shared_files');

  /// 최신 파일이 위로 오도록 내림차순 정렬한다.
  Stream<List<FileEntry>> watchFiles() {
    return _collection
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              readableFileEntries([for (final doc in snapshot.docs) (doc.id, doc.data())]),
        );
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
    final task = _storage
        .ref(storagePath)
        .putData(bytes, SettableMetadata(contentType: contentType));
    return (docId: docId, storagePath: storagePath, task: task);
  }

  Future<void> registerFile(FileEntry entry) => _collection.doc(entry.id).set(entry.toJson());

  /// 업로드는 성공했지만 [registerFile]이 실패해 Firestore 문서가 없는 Storage 파일을 지운다.
  /// 문서가 없으면 목록(watchFiles)에 절대 나타나지 않아 앱에서 발견·삭제할 방법이 없는데도
  /// 용량은 차지하기 때문이다. 어디까지나 최선을 다한 정리라 실패해도 예외를 던지지 않는다 —
  /// 특히 storage.rules의 삭제 규칙은 (관리자가 아니면) Firestore 문서의 uploadedByEmail을
  /// 교차 조회하는데 이 경우엔 문서가 없어, 일반 사용자의 정리 시도는 규칙에 거부될 수 있다.
  Future<void> discardUnregisteredUpload(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {}
  }

  Future<String> getDownloadUrl(String storagePath) => _storage.ref(storagePath).getDownloadURL();

  /// 다운로드 URL을 직접 스트리밍으로 받아온다. firebase_storage의 getData()는 진행률
  /// 콜백이 없어서, 진행 상황을 보여주려면 http로 직접 받아야 한다(Storage 버킷 CORS
  /// 설정 필요).
  Future<Uint8List> downloadBytes(
    String storagePath, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = await getDownloadUrl(storagePath);
    final client = http.Client();
    final abort = Completer<void>();
    Timer? stallTimer;
    // 응답 헤더를 기다리는 동안에도, 청크를 받을 때마다도 이 타이머를 다시 건다 — 어느
    // 시점에서든 _stallTimeout 동안 진전이 없으면 요청을 실제로 취소한다(Future.timeout과
    // 달리 연결 자체가 끊겨 리소스가 새지 않는다).
    void resetStallTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_stallTimeout, () {
        if (!abort.isCompleted) abort.complete();
      });
    }

    try {
      resetStallTimer();
      final http.StreamedResponse response;
      try {
        response = await client.send(
          http.AbortableRequest('GET', Uri.parse(url), abortTrigger: abort.future),
        );
      } on http.RequestAbortedException {
        throw ApiException('서버 응답이 없습니다. 잠시 후 다시 시도해주세요.');
      }

      final total = response.contentLength;
      final bytes = <int>[];
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          resetStallTimer();
          bytes.addAll(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } on http.RequestAbortedException {
        throw ApiException('다운로드가 지연되어 중단되었습니다. 잠시 후 다시 시도해주세요.');
      }
      return Uint8List.fromList(bytes);
    } finally {
      stallTimer?.cancel();
      client.close();
    }
  }

  /// Storage 파일을 먼저 지우고, 성공했을 때만 Firestore 문서를 지운다. 순서를 바꾸면
  /// Storage 삭제가 실패했을 때 목록에서는 사라졌는데 Storage에는 파일이 남아 용량을
  /// 조용히 차지하는(눈에 안 보이는) 상황이 생긴다.
  ///
  /// Storage는 지워졌는데 그 직후 Firestore 문서 삭제만 실패하면(네트워크 문제 등), 문서는
  /// 목록에 남고 Storage 파일만 없는 상태가 된다. 이때 재시도하면 Storage 삭제가
  /// object-not-found로 실패해 Firestore 삭제까지 아예 못 가는 문제가 있었다 — 이미 지워진
  /// 상태로 보고 통과시켜서, 재시도만으로 스스로 복구되게 한다.
  Future<void> deleteFile(FileEntry entry) async {
    try {
      await _storage.ref(entry.storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
    await _collection.doc(entry.id).delete();
  }
}
