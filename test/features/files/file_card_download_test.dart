import 'package:daily_snapshot/core/auth/auth_provider.dart';
import 'package:daily_snapshot/features/files/application/file_provider.dart';
import 'package:daily_snapshot/features/files/data/file_entry.dart';
import 'package:daily_snapshot/features/files/presentation/file_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 실제 다운로드(Storage/네트워크) 대신 호출 여부만 기록한다.
class _RecordingDownloadNotifier extends FileDownloadNotifier {
  final List<String> downloaded = [];

  @override
  Future<void> download(FileEntry entry) async => downloaded.add(entry.id);
}

final _entry = FileEntry(
  id: 'f1',
  name: '보고서.pdf',
  sizeBytes: 2 * 1024 * 1024,
  contentType: 'application/pdf',
  storagePath: 'shared_files/f1/보고서.pdf',
  uploadedByEmail: 'someone@example.com',
  uploadedAt: DateTime(2026, 9, 28, 9),
);

Future<_RecordingDownloadNotifier> _pumpCard(WidgetTester tester) async {
  final notifier = _RecordingDownloadNotifier();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUidProvider.overrideWithValue(const AsyncData('test-uid')),
        authEmailProvider.overrideWithValue(const AsyncData('me@example.com')),
        isAdminProvider.overrideWithValue(const AsyncData(false)),
        filesProvider.overrideWithValue(AsyncData([_entry])),
        fileDownloadProvider.overrideWith(() => notifier),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: FileCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets('download asks for confirmation and does nothing when cancelled', (tester) async {
    final notifier = await _pumpCard(tester);

    await tester.tap(find.byTooltip('다운로드'));
    await tester.pumpAndSettle();

    expect(find.text('파일 다운로드'), findsOneWidget);
    expect(find.textContaining('보고서.pdf'), findsWidgets);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(notifier.downloaded, isEmpty);
  });

  testWidgets('download starts after confirming', (tester) async {
    final notifier = await _pumpCard(tester);

    await tester.tap(find.byTooltip('다운로드'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '다운로드'));
    await tester.pumpAndSettle();

    expect(notifier.downloaded, ['f1']);
  });
}
