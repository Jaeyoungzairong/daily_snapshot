import 'dart:async';

import 'package:daily_snapshot/core/auth/account_dialog.dart';
import 'package:daily_snapshot/core/auth/auth_provider.dart';
import 'package:daily_snapshot/core/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 테스트용 로그인 uid(로그인 안 됐으면 null).
class _TestUid extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final _uidProvider = NotifierProvider<_TestUid, String?>(_TestUid.new);

/// signInWithGoogle만 흉내 낸다: 실제처럼 Firebase 로그인(uid 생김)이 먼저 끝나고, 승인 확인은
/// [approval]이 완료될 때까지 기다린다. 미승인이면 실제처럼 로그아웃(uid 제거) 후 예외를 던진다.
class _FakeAuthService implements AuthService {
  _FakeAuthService(this.container);

  final ProviderContainer container;
  final Completer<bool> approval = Completer<bool>();

  @override
  Future<void> signInWithGoogle() async {
    container.read(_uidProvider.notifier).set('new-uid');
    if (!await approval.future) {
      container.read(_uidProvider.notifier).set(null);
      throw const NotApprovedException();
    }
  }

  @override
  bool get isGoogleAccountLinked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeAuthService> _pumpDialog(WidgetTester tester) async {
  late final _FakeAuthService auth;
  final container = ProviderContainer(
    overrides: [
      authServiceProvider.overrideWith((ref) => auth),
      authUidProvider.overrideWith((ref) => AsyncData(ref.watch(_uidProvider))),
      authEmailProvider.overrideWith(
        (ref) => AsyncData(ref.watch(_uidProvider) == null ? null : 'user@example.com'),
      ),
      androidAccessEnabledProvider.overrideWithValue(const AsyncData(false)),
    ],
  );
  addTearDown(container.dispose);
  auth = _FakeAuthService(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => const AccountDialog()),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
  // 테스트는 웹이 아니라(kIsWeb == false) 안드로이드용 Google 로그인 화면이 보인다.
  await tester.tap(find.text('Google로 로그인'));
  await tester.pump();
  return auth;
}

void main() {
  // 예전엔 Firebase 로그인으로 uid가 잠깐 생기는 순간 다이얼로그가 "로그인 완료"로 보고 닫혀서,
  // 뒤이은 미승인 안내가 사라진 다이얼로그에 버려졌다(설명 없이 창만 닫힘).
  testWidgets('keeps the dialog open and shows the not-approved message', (tester) async {
    final auth = await _pumpDialog(tester);

    // uid는 생겼지만 승인 확인 중 — 아직 닫히면 안 된다.
    expect(find.byType(AccountDialog), findsOneWidget);

    auth.approval.complete(false);
    await tester.pumpAndSettle();

    expect(find.byType(AccountDialog), findsOneWidget);
    expect(find.textContaining('관리자 승인이 필요한 이메일입니다'), findsOneWidget);
  });

  testWidgets('closes the dialog once an approved sign-in finishes', (tester) async {
    final auth = await _pumpDialog(tester);
    expect(find.byType(AccountDialog), findsOneWidget);

    auth.approval.complete(true);
    await tester.pumpAndSettle();

    expect(find.byType(AccountDialog), findsNothing);
  });
}
