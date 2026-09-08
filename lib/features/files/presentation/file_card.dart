import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/url_opener.dart';
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

    try {
      await ref.read(fileUploadProvider.notifier).uploadFiles(files);
    } on FileCountLimitExceededException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일은 최대 $maxFileCount개까지 올릴 수 있습니다.')),
      );
    } on FileTooLargeException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${error.fileName}: 파일 하나는 최대 ${Formatters.fileSize(maxFileSizeBytes)}까지 올릴 수 있습니다.')),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filesAsync.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(message: error.toString()),
          data: (files) {
            if (files.isEmpty) {
              return Text(
                '올라온 파일이 없습니다. + 버튼을 눌러 추가해보세요.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
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
            '${uploadProgress.fileName} 업로드 중… ${(uploadProgress.progress * 100).round()}%',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: uploadProgress.progress),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: uploadProgress == null ? () => _pickAndUpload(context, ref) : null,
          icon: const Icon(Icons.upload_file),
          label: const Text('파일 추가'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('파일 삭제'),
        content: Text('"${entry.name}"을(를) 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
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
    final extension = entry.name.contains('.') ? entry.name.split('.').last : null;
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
