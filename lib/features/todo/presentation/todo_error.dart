import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 할일/메모 Firestore 스트림에서 발생한 에러를 사용자에게 보여줄 한국어 메시지로 바꾼다.
/// TodoCard/MemoCard가 같은 repository를 구독해 같은 종류의 에러를 겪으므로 공유한다.
String describeTodoDataError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '승인이 해제되었습니다. 관리자에게 문의해주세요.';
      case 'unavailable':
        return '네트워크 연결을 확인해주세요.';
    }
  }
  return '일시적인 오류가 발생했습니다. 다시 시도해주세요.';
}

/// 할일/메모 변경 작업([action])을 실행하고, 저장에 실패하면 스낵바로 알린다. 성공하면
/// true, 실패하면 false를 반환한다. 위젯이 사라진 뒤에도 안전하도록 await 전에
/// ScaffoldMessenger를 미리 잡아둔다.
Future<bool> runTodoWrite(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    return true;
  } catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('저장하지 못했습니다. ${describeTodoDataError(error)}')));
    return false;
  }
}
