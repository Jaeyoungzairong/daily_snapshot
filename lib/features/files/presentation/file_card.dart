import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/url_opener.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/loading_error_view.dart';
import '../application/file_provider.dart';
import '../data/file_entry.dart';
import '../data/file_mime.dart';

const Map<String, IconData> _iconByExtension = {
  'pdf': Icons.picture_as_pdf_outlined,
  'png': Icons.image_outlined,
  'jpg': Icons.image_outlined,
  'jpeg': Icons.image_outlined,
  'gif': Icons.image_outlined,
  'webp': Icons.image_outlined,
  'txt': Icons.description_outlined,
  'csv': Icons.table_chart_outlined,
  'zip': Icons.folder_zip_outlined,
  'doc': Icons.description_outlined,
  'docx': Icons.description_outlined,
  'xls': Icons.table_chart_outlined,
  'xlsx': Icons.table_chart_outlined,
  'ppt': Icons.slideshow_outlined,
  'pptx': Icons.slideshow_outlined,
  'mp4': Icons.videocam_outlined,
  'mp3': Icons.audiotrack_outlined,
};

IconData _iconFor(String? extension) => _iconByExtension[extension?.toLowerCase()] ?? Icons.insert_drive_file_outlined;

enum _DuplicateChoice { cancel, skipDuplicates, uploadAnyway }

/// 이미 목록에 같은 이름의 파일이 있을 때 어떻게 할지 묻는다. 무조건 막거나(관리자 아니면
/// 재업로드할 방법이 없어짐) 조용히 이름을 바꾸지 않고, 판단을 사용자에게 맡긴다.
Future<_DuplicateChoice> _confirmDuplicateNames(BuildContext context, List<String> duplicateNames) async {
  final choice = await showDialog<_DuplicateChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('동일한 이름의 파일이 있습니다'),
      content: Text('이미 목록에 있는 파일명과 같습니다:\n${duplicateNames.join(', ')}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _DuplicateChoice.cancel),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _DuplicateChoice.skipDuplicates),
          child: const Text('중복 제외하고 업로드'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _DuplicateChoice.uploadAnyway),
          child: const Text('그래도 업로드'),
        ),
      ],
    ),
  );
  return choice ?? _DuplicateChoice.cancel;
}

class FileCard extends ConsumerWidget {
  const FileCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final authState = ref.watch(authUidProvider);

    return DashboardCard(
      title: '공유 파일함',
      icon: Icons.folder_shared_outlined,
      accentColor: theme.extension<AppAccentColors>()?.files,
      child: authState.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error.toString()),
        data: (uid) => uid == null
            ? Text(
                '로그인 후 이용할 수 있습니다. "할 일" 카드에서 먼저 로그인해주세요.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              )
            : const _FileListSection(),
      ),
    );
  }
}

class _FileListSection extends ConsumerWidget {
  const _FileListSection();

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;

    final existingNames = (ref.read(filesProvider).value ?? []).map((entry) => entry.name).toSet();
    final duplicateNames = files.map((file) => file.name).where(existingNames.contains).toSet();

    var filesToUpload = files;
    if (duplicateNames.isNotEmpty) {
      if (!context.mounted) return;
      final choice = await _confirmDuplicateNames(context, duplicateNames.toList());
      if (choice == _DuplicateChoice.cancel) return;
      if (choice == _DuplicateChoice.skipDuplicates) {
        filesToUpload = files.where((file) => !duplicateNames.contains(file.name)).toList();
        if (filesToUpload.isEmpty) return;
      }
    }

    try {
      final result = await ref.read(fileUploadProvider.notifier).uploadFiles(filesToUpload);
      if (!context.mounted || !result.hasFailures) return;
      final summary = result.failures.map((f) => '${f.fileName}: ${f.reason}').join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${filesToUpload.length}개 중 ${result.succeededCount}개 업로드 완료 · 실패: $summary')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 중 문제가 발생했습니다: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filesAsync = ref.watch(filesProvider);
    final uploadProgress = ref.watch(fileUploadProvider);
    final isAdmin = ref.watch(isAdminProvider).value ?? false;
    final fileCount = filesAsync.value?.length ?? 0;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filesAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(message: error.toString()),
          data: (files) {
            if (files.isEmpty) {
              return Text('올라온 파일이 없습니다. + 버튼을 눌러 추가해보세요.', style: captionStyle);
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 660),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final entry in files) _FileRow(entry: entry, canDelete: isAdmin),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (uploadProgress != null) ...[
          Text(
            uploadProgress.total > 1
                ? '(${uploadProgress.index}/${uploadProgress.total}) ${uploadProgress.fileName} 업로드 중… '
                    '${(uploadProgress.progress * 100).round()}%'
                : '${uploadProgress.fileName} 업로드 중… ${(uploadProgress.progress * 100).round()}%',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: uploadProgress.progress),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: uploadProgress == null ? () => _pickAndUpload(context, ref) : null,
              icon: const Icon(Icons.upload_file),
              label: const Text('파일 추가'),
            ),
            Text('$fileCount/$maxFileCount개', style: captionStyle),
          ],
        ),
      ],
    );
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({required this.entry, required this.canDelete});

  final FileEntry entry;
  final bool canDelete;

  Future<void> _preview(WidgetRef ref) async {
    final url = await ref.read(fileRepositoryProvider).getDownloadUrl(entry.storagePath);
    openUrl(url);
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final url = await ref.read(fileRepositoryProvider).getDownloadUrl(entry.storagePath);
      openUrl(url);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다운로드 중 문제가 발생했습니다: $error')),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: '파일 삭제',
      message: '"${entry.name}"을(를) 삭제할까요? 되돌릴 수 없습니다.',
    );
    if (!confirmed) return;
    try {
      await ref.read(fileRepositoryProvider).deleteFile(entry);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 중 문제가 발생했습니다: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final extension = entry.extension;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(_iconFor(extension), size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                Text(
                  '${Formatters.fileSize(entry.sizeBytes)} · ${entry.uploadedByEmail} · ${Formatters.dateTime(entry.uploadedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: captionStyle,
                ),
              ],
            ),
          ),
          if (isPreviewableExtension(extension))
            IconButton(
              onPressed: () => _preview(ref),
              icon: const Icon(Icons.visibility_outlined, size: 20),
              tooltip: '미리보기',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: () => _download(context, ref),
            icon: const Icon(Icons.download_outlined, size: 20),
            tooltip: '다운로드',
            visualDensity: VisualDensity.compact,
          ),
          if (canDelete)
            IconButton(
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '삭제',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
