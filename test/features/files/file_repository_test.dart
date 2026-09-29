import 'package:daily_snapshot/features/files/data/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _validDoc(String name) => {
  'name': name,
  'sizeBytes': 1024,
  'contentType': 'application/pdf',
  'storagePath': 'shared_files/x/$name',
  'uploadedByEmail': 'someone@example.com',
  'uploadedAt': '2026-09-29T09:00:00.000',
};

void main() {
  group('readableFileEntries', () {
    // 공유 컬렉션이라 문서 하나가 깨지면 예전엔 모든 사용자의 파일함이 에러 화면이 됐다.
    test('skips malformed documents and keeps the rest in order', () {
      final entries = readableFileEntries([
        ('a', _validDoc('a.pdf')),
        ('broken-missing', {'name': 'b.pdf'}),
        ('broken-type', {..._validDoc('c.pdf'), 'sizeBytes': '1024'}),
        ('broken-date', {..._validDoc('d.pdf'), 'uploadedAt': 'not-a-date'}),
        ('e', _validDoc('e.pdf')),
      ]);

      expect(entries.map((entry) => entry.id), ['a', 'e']);
      expect(entries.first.name, 'a.pdf');
    });

    test('returns an empty list when nothing is readable', () {
      expect(readableFileEntries([('x', <String, dynamic>{})]), isEmpty);
    });
  });
}
