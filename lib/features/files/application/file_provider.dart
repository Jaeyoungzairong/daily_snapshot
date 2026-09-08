import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/file_entry.dart';
import '../data/file_mime.dart';
import '../data/file_repository.dart';

/// Storage 용량을 무한정 차지하지 않도록 개수와 파일 하나당 용량에 상한을 둔다.
const int maxFileCount = 30;
const int maxFileSizeBytes = 100 * 1024 * 1024;

/// [FileUploadNotifier.uploadFiles]가 개수 상한(maxFileCount)에 걸려 더 이상 올릴 수
/// 없을 때 던진다.
class FileCountLimitExceededException implements Exception {
  const FileCountLimitExceededException();
}

/// 파일 하나가 용량 상한(maxFileSizeBytes)을 넘을 때 던진다.
class FileTooLargeException implements Exception {
  const FileTooLargeException(this.fileName);
  final String fileName;
}

final fileRepositoryProvider = Provider<FileRepository>((ref) => FileRepository());

final filesProvider = StreamProvider<List<FileEntry>>((ref) {
  return ref.watch(fileRepositoryProvider).watchFiles();
});

/// 업로드 중인 파일명과 진행률(0.0~1.0). 업로드 중이 아니면 null.
class UploadProgress {
  const UploadProgress({required this.fileName, required this.progress});
  final String fileName;
  final double progress;
}

class FileUploadNotifier extends Notifier<UploadProgress?> {
  @override
  UploadProgress? build() => null;

  /// 선택된 파일들을 순서대로(동시에 아니라 하나씩) 업로드한다. 도중에 개수/용량
  /// 상한에 걸리면 그 시점까지는 이미 업로드된 파일을 남겨둔 채 예외를 던진다.
  Future<void> uploadFiles(List<PlatformFile> files) async {
    final repository = ref.read(fileRepositoryProvider);
    final email = ref.read(authEmailProvider).value;
    if (email == null) {
      // 이 시점엔 이미 로그인 상태(uid 있음)로 확인된 뒤라 email도 당연히 있어야 한다.
      // 그런데도 null이면 조용히 넘어가지 않고 바로 에러로 드러내서 원인을 알 수 있게 한다.
      throw StateError('로그인 이메일을 확인할 수 없습니다. 다시 로그인해주세요.');
    }

    var count = (ref.read(filesProvider).value ?? []).length;
    try {
      for (final file in files) {
        if (count >= maxFileCount) {
          throw const FileCountLimitExceededException();
        }
        // 브라우저가 알려주는 크기(I/O 없이 바로 확인 가능)로 먼저 걸러서, 너무 큰
        // 파일은 굳이 메모리에 읽어들이지 않게 한다.
        final knownSize = file.lengthSync();
        if (knownSize != null && knownSize > maxFileSizeBytes) {
          throw FileTooLargeException(file.name);
        }

        final bytes = await file.readAsBytes();
        if (bytes.length > maxFileSizeBytes) {
          throw FileTooLargeException(file.name);
        }

        state = UploadProgress(fileName: file.name, progress: 0);
        final upload = repository.startUpload(
          name: file.name,
          bytes: bytes,
          contentType: mimeTypeForExtension(file.extension),
        );
        final subscription = upload.task.snapshotEvents.listen((snapshot) {
          final total = snapshot.totalBytes;
          state = UploadProgress(
            fileName: file.name,
            progress: total == 0 ? 0 : snapshot.bytesTransferred / total,
          );
        });
        await upload.task;
        await subscription.cancel();

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
      }
    } finally {
      state = null;
    }
  }
}

final fileUploadProvider = NotifierProvider<FileUploadNotifier, UploadProgress?>(FileUploadNotifier.new);
