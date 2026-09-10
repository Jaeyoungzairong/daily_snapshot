import 'package:flutter/material.dart';

/// 삭제 확인 버튼 색. 테마의 colorScheme.error를 쓰지 않는 이유는, M3 다크 테마에서
/// error 톤이 저채도로 반전되어(errorContainer와 반대 방향) 라이트/다크에서 버튼이
/// 서로 다른 강도의 빨강으로 보이기 때문이다 — 고정값을 써서 항상 같은 톤을 유지한다.
const Color _destructiveColor = Color(0xFFB3261E);

/// 실수 방지용 확인 다이얼로그. 사용자가 [confirmLabel] 버튼을 눌렀을 때만 true를 반환한다.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '삭제',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        // title/actions 슬롯은 내용 크기만큼만 차지하도록 설계돼 있어 버튼을 폭 꽉
        // 차게 늘리기 까다롭다. content 슬롯 하나에 전부 넣으면 다이얼로그가 이미 정한
        // 폭을 그대로 받아서 Expanded가 자연스럽게 동작한다(AccountDialog와 동일 패턴).
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flutter M3 AlertDialog의 기본 제목 스타일(headlineSmall)과 맞춰서,
              // 이 앱의 다른(기본 title 슬롯을 쓰는) 다이얼로그와 글자 크기가 어긋나지
              // 않게 한다.
              Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: theme.colorScheme.onSurface,
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _destructiveColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(confirmLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}
