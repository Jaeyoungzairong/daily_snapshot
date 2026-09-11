import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/utils/formatters.dart';
import '../data/file_entry.dart';
import '../data/file_mime.dart';
import '../data/file_repository.dart';

/// Storage 용량을 무한정 차지하지 않도록 개수와 파일 하나당 용량에 상한을 둔다.
const int maxFileCount = 30;
const int maxFileSizeBytes = 150 * 1024 * 1024;

/// 여러 파일을 한 번에 올릴 때 실패한 파일 하나의 정보.
class UploadFailure {
  const UploadFailure({required this.fileName, required this.reason});
  final String fileName;
  final String reason;
}

/// [FileUploadNotifier.uploadFiles] 결과. 일부만 실패해도 나머지는 계속 시도하므로,
/// 성공 개수와 실패 목록을 같이 돌려준다.
class UploadResult {
  const UploadResult({required this.succeededCount, required this.failures});
  final int succeededCount;
  final List<UploadFailure> failures;
  bool get hasFailures => failures.isNotEmpty;
}

final fileRepositoryProvider = Provider<FileRepository>((ref) => FileRepository());

final filesProvider = StreamProvider<List<FileEntry>>((ref) {
  return ref.watch(fileRepositoryProvider).watchFiles();
});

/// 업로드 중인 파일명과 진행률(0.0~1.0), 여러 개를 한 번에 올릴 때 전체 중 몇 번째인지.
/// 업로드 중이 아니면 null.
class UploadProgress {
  const UploadProgress({
    required this.fileName,
    required this.progress,
    required this.index,
    required this.total,
  });
  final String fileName;
  final double progress;
  final int index;
  final int total;
}

class FileUploadNotifier extends Notifier<UploadProgress?> {
  @override
  UploadProgress? build() => null;

  /// 선택된 파일들을 순서대로(동시에 아니라 하나씩) 업로드한다. 파일 하나가 개수/용량
  /// 상한에 걸리거나 업로드 자체가 실패해도 그 파일만 건너뛰고 나머지는 계속 시도한다 —
  /// 예전엔 중간에 하나만 실패해도 그 뒤 파일들은 시도조차 안 됐다.
  Future<UploadResult> uploadFiles(List<PlatformFile> files) async {
    final repository = ref.read(fileRepositoryProvider);
    final email = ref.read(authEmailProvider).value;
    if (email == null) {
      // 이 시점엔 이미 로그인 상태(uid 있음)로 확인된 뒤라 email도 당연히 있어야 한다.
      // 그런데도 null이면 조용히 넘어가지 않고 바로 에러로 드러내서 원인을 알 수 있게 한다.
      throw StateError('로그인 이메일을 확인할 수 없습니다. 다시 로그인해주세요.');
    }

    var count = (ref.read(filesProvider).value ?? []).length;
    var succeeded = 0;
    final failures = <UploadFailure>[];

    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        if (count >= maxFileCount) {
          failures.add(
            UploadFailure(fileName: file.name, reason: '파일은 최대 $maxFileCount개까지 올릴 수 있습니다.'),
          );
          continue;
        }

        // 브라우저가 알려주는 크기(I/O 없이 바로 확인 가능)로 먼저 걸러서, 너무 큰
        // 파일은 굳이 메모리에 읽어들이지 않게 한다.
        final knownSize = file.lengthSync();
        if (knownSize != null && knownSize > maxFileSizeBytes) {
          failures.add(
            UploadFailure(
              fileName: file.name,
              reason: '파일 하나는 최대 ${Formatters.fileSize(maxFileSizeBytes)}까지 올릴 수 있습니다.',
            ),
          );
          continue;
        }

        try {
          final bytes = await file.readAsBytes();
          if (bytes.length > maxFileSizeBytes) {
            failures.add(
              UploadFailure(
                fileName: file.name,
                reason: '파일 하나는 최대 ${Formatters.fileSize(maxFileSizeBytes)}까지 올릴 수 있습니다.',
              ),
            );
            continue;
          }

          state = UploadProgress(
            fileName: file.name,
            progress: 0,
            index: i + 1,
            total: files.length,
          );
          final upload = repository.startUpload(
            name: file.name,
            bytes: bytes,
            contentType: mimeTypeForExtension(file.extension),
          );
          final subscription = upload.task.snapshotEvents.listen((snapshot) {
            final totalBytes = snapshot.totalBytes;
            state = UploadProgress(
              fileName: file.name,
              progress: totalBytes == 0 ? 0 : snapshot.bytesTransferred / totalBytes,
              index: i + 1,
              total: files.length,
            );
          });
          try {
            await upload.task;
          } finally {
            await subscription.cancel();
          }

          await repository.registerFile(
            FileEntry(
              id: upload.docId,
              name: file.name,
              sizeBytes: bytes.length,
              contentType: mimeTypeForExtension(file.extension),
              storagePath: upload.storagePath,
              uploadedByEmail: email,
              uploadedAt: DateTime.now(),
            ),
          );
          count++;
          succeeded++;
        } catch (error) {
          failures.add(UploadFailure(fileName: file.name, reason: error.toString()));
        }
      }
    } finally {
      state = null;
    }

    return UploadResult(succeededCount: succeeded, failures: failures);
  }
}

final fileUploadProvider = NotifierProvider<FileUploadNotifier, UploadProgress?>(
  FileUploadNotifier.new,
);

/// 다운로드 중인 파일 ID와 진행률(0.0~1.0). 다운로드 중이 아니면 null. 한 번에 하나만
/// 다운로드한다고 가정 — fileId로 어느 행이 진행 중인지 UI에서 구분한다.
class DownloadProgress {
  const DownloadProgress({required this.fileId, required this.progress});
  final String fileId;
  final double progress;
}

class FileDownloadNotifier extends Notifier<DownloadProgress?> {
  @override
  DownloadProgress? build() => null;

  Future<void> download(FileEntry entry) async {
    final repository = ref.read(fileRepositoryProvider);
    try {
      final bytes = await repository.downloadBytes(
        entry.storagePath,
        onProgress: (received, total) {
          state = DownloadProgress(
            fileId: entry.id,
            progress: total == null || total == 0 ? 0 : received / total,
          );
        },
      );
      saveBytes(bytes, fileName: entry.name, mimeType: entry.contentType);
    } finally {
      state = null;
    }
  }
}

final fileDownloadProvider = NotifierProvider<FileDownloadNotifier, DownloadProgress?>(
  FileDownloadNotifier.new,
);
