import 'package:flutter/material.dart';

/// 실수 방지용 확인 다이얼로그. 사용자가 [confirmLabel] 버튼을 눌렀을 때만 true를 반환한다.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '삭제',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}
