import 'package:daily_snapshot/core/auth/auth_service.dart';
import 'package:daily_snapshot/core/auth/sign_in_prompt.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isTerminalSignInLinkError', () {
    test('PendingEmailNotFoundException is always terminal (no email to retry with)', () {
      expect(
        isTerminalSignInLinkError(const PendingEmailNotFoundException(), hadStoredEmail: true),
        isTrue,
      );
      expect(
        isTerminalSignInLinkError(const PendingEmailNotFoundException(), hadStoredEmail: false),
        isTrue,
      );
    });

    test('NotApprovedException is retryable (link is not consumed yet)', () {
      expect(
        isTerminalSignInLinkError(const NotApprovedException(), hadStoredEmail: true),
        isFalse,
      );
    });

    test('expired-action-code is always terminal', () {
      expect(
        isTerminalSignInLinkError(
          FirebaseAuthException(code: 'expired-action-code'),
          hadStoredEmail: true,
        ),
        isTrue,
      );
      expect(
        isTerminalSignInLinkError(
          FirebaseAuthException(code: 'expired-action-code'),
          hadStoredEmail: false,
        ),
        isTrue,
      );
    });

    test(
      'invalid-action-code is terminal with a stored email, retryable with a manually typed one',
      () {
        expect(
          isTerminalSignInLinkError(
            FirebaseAuthException(code: 'invalid-action-code'),
            hadStoredEmail: true,
          ),
          isTrue,
        );
        expect(
          isTerminalSignInLinkError(
            FirebaseAuthException(code: 'invalid-action-code'),
            hadStoredEmail: false,
          ),
          isFalse,
        );
      },
    );

    test('unrecognized FirebaseAuthException codes are treated as retryable', () {
      expect(
        isTerminalSignInLinkError(
          FirebaseAuthException(code: 'network-request-failed'),
          hadStoredEmail: true,
        ),
        isFalse,
      );
    });

    test('non-Firebase exceptions (e.g. generic network errors) are retryable', () {
      expect(isTerminalSignInLinkError(Exception('boom'), hadStoredEmail: true), isFalse);
    });
  });
}
