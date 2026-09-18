import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/confirm_dialog.dart';
import '../widgets/dialog_header_icon.dart';
import 'auth_provider.dart';
import 'sign_in_prompt.dart';

/// 로그인/로그아웃을 모두 처리하는 계정 다이얼로그. 로그인 안 됐으면 기존 [SignInPrompt]를
/// 그대로 보여주고(내부 상태머신 재사용), 로그인 성공 시 자동으로 닫힌다. 로그인 됐으면
/// 이메일과 로그아웃 버튼을 보여준다.
///
/// [onBeforeSignOut]은 로그아웃 직전에 호출된다 — 예를 들어 다른 기능이 디바운스 저장
/// 중인 내용을 flush해야 하는 경우 여기 넘긴다. core 레이어인 이 파일이 특정 feature의
/// provider를 직접 알 필요가 없도록 콜백으로 분리했다.
class AccountDialog extends ConsumerStatefulWidget {
  const AccountDialog({super.key, this.onBeforeSignOut});

  final Future<void> Function()? onBeforeSignOut;

  @override
  ConsumerState<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends ConsumerState<AccountDialog> {
  bool _signingOut = false;
  bool _linkingGoogle = false;

  Future<void> _signOut() async {
    // 계정 다이얼로그를 직접 열고 로그아웃 버튼을 눌러야만 여기 도달하므로, 그 자체가
    // 이미 의도 확인 단계다 — 별도 확인 다이얼로그를 한 번 더 띄우지 않는다.
    if (_signingOut) return;

    setState(() => _signingOut = true);

    // 저장 타이머가 아직 안 돌았다면(로그아웃 직전에 입력한 경우), 로그인 상태가
    // 사라지기 전에 지금 즉시 저장해서 마지막 편집 내용이 유실되지 않게 한다.
    try {
      await widget.onBeforeSignOut?.call();
    } catch (_) {}

    if (!mounted) return;
    try {
      // signOut() 직후 아직 살아있는 할일/메모/파일함 리스너가 인증 컨텍스트 소실로
      // permission-denied를 받을 수 있는데, 이걸 dashboard_page.dart가 "다른 기기에서
      // 로그아웃당함"으로 오인해 세션 만료 안내를 띄우지 않도록 정상 로그아웃도 미리
      // 선점한다(_forceLogoutAllDevices와 동일한 이유).
      ref.read(sessionInvalidationHandledProvider.notifier).set(true);
      await ref.read(authServiceProvider).signOut();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      ref.read(sessionInvalidationHandledProvider.notifier).set(false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('로그아웃에 실패했습니다. 다시 시도해주세요.')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  /// 다른 PC에 로그인한 채로 로그아웃을 잊고 나왔을 때를 대비한 안전장치. 이 계정으로
  /// 로그인된 모든 세션(이 기기 포함)을 무효화한다 — 특정 기기만 골라 끊을 방법이 없어서
  /// "전체"로만 동작한다(AuthService.forceLogoutAllDevices 참고).
  Future<void> _forceLogoutAllDevices() async {
    if (_signingOut) return;
    final confirmed = await confirmAction(
      context,
      title: '모든 기기에서 로그아웃',
      message: '이 기기를 포함해 로그인된 모든 기기에서 로그아웃됩니다.\n다시 로그인해야 합니다.',
      confirmLabel: '로그아웃',
    );
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    try {
      await widget.onBeforeSignOut?.call();
    } catch (_) {}

    if (!mounted) return;
    try {
      // 이 기기는 본인이 의도적으로 누른 동작이므로, dashboard_page.dart의 세션 무효화
      // 감지(isSessionValidProvider)가 이 요청으로 갱신된 forceLogoutAfter를 보고 "세션이
      // 만료되었습니다" 안내를 또 띄우지 않도록 미리 선점한다. 아래에서 실패하면(로그아웃
      // 자체는 안 된 상태) 다시 풀어서, 이후 진짜 세션 무효화를 놓치지 않게 한다.
      ref.read(sessionInvalidationHandledProvider.notifier).set(true);
      await ref.read(authServiceProvider).forceLogoutAllDevices();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      ref.read(sessionInvalidationHandledProvider.notifier).set(false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('로그아웃에 실패했습니다. 다시 시도해주세요.')));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  /// 웹 전용. 지금 로그인된 회사메일 계정에 Google 계정을 연동해서, 안드로이드에서
  /// 그 Google 계정으로 로그인해도(signInWithGoogle) 같은 uid로 들어와 할일/메모/
  /// 파일함 데이터를 그대로 이어서 볼 수 있게 한다 — 안드로이드는 이메일 링크를 받지
  /// 않으므로 이 연동이 사전에 웹에서 1회 되어 있어야 한다.
  Future<void> _linkGoogleAccount() async {
    if (_linkingGoogle) return;
    setState(() => _linkingGoogle = true);
    try {
      await ref.read(authServiceProvider).linkGoogleAccount();
    } on FirebaseAuthException catch (error) {
      // 연동 팝업을 사용자가 그냥 닫은 경우는 에러가 아니라 정상적인 흐름이다.
      if (error.code == 'popup-closed-by-user' || error.code == 'cancelled-popup-request') {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeAuthError(error))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeAuthError(error))));
      }
    } finally {
      if (mounted) setState(() => _linkingGoogle = false);
    }
  }

  /// 웹 전용. [_linkGoogleAccount]로 걸어둔 연동을 해제하고, 곧바로 모든 기기에서
  /// 로그아웃까지 함께 진행한다. 연동을 끊는 목적 자체가 대개 "이 Google 계정으로
  /// 안드로이드에 로그인해 있는 세션의 접근을 지금 끊고 싶다"는 것이라, 연동 해제만
  /// 해서는 그 기기의 이미 발급된 세션이 계속 유효한 채로 남는다(uid/이메일이 그대로라
  /// unlink 자체는 토큰을 무효화하지 않음) — forceLogoutAllDevices를 같이 호출해야
  /// forceLogoutAfter가 갱신되어 그 세션도 실제로 막힌다. unlink가 currentUser를
  /// 참조하므로 forceLogoutAllDevices(내부에서 signOut까지 함)보다 반드시 먼저 실행한다.
  Future<void> _unlinkGoogleAccount() async {
    if (_signingOut) return;
    final confirmed = await confirmAction(
      context,
      title: 'Google 계정 연동 해제',
      message: 'Google 계정 연동을 해제하고, 이 기기를 포함해 로그인된 모든 기기에서 로그아웃됩니다.\n다시 로그인해야 합니다.',
      confirmLabel: '해제',
    );
    if (!confirmed || !mounted) return;

    setState(() => _signingOut = true);
    try {
      await widget.onBeforeSignOut?.call();
    } catch (_) {}

    if (!mounted) return;
    try {
      ref.read(sessionInvalidationHandledProvider.notifier).set(true);
      await ref.read(authServiceProvider).unlinkGoogleAccount();
      await ref.read(authServiceProvider).forceLogoutAllDevices();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      ref.read(sessionInvalidationHandledProvider.notifier).set(false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeAuthError(error))));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이 다이얼로그 안에서 로그인이 완료되면(이메일 링크 확인 등) 자동으로 닫아준다.
    ref.listen(authUidProvider, (previous, next) {
      if (previous?.value == null && next.value != null) {
        Navigator.of(context).pop();
      }
    });

    final authState = ref.watch(authUidProvider);
    final email = ref.watch(authEmailProvider).value;
    final signedIn = authState.value != null;
    final colorScheme = Theme.of(context).colorScheme;
    final androidAccessEnabled = ref.watch(androidAccessEnabledProvider).value ?? false;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.all(24),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogHeaderIcon(
              icon: signedIn ? Icons.account_circle : Icons.account_circle_outlined,
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 24),
            authState.when(
              loading: () =>
                  const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
              error: (error, _) => Text('로그인 상태를 확인할 수 없습니다: $error'),
              data: (uid) => uid == null
                  ? const SignInPrompt()
                  : _SignedInContent(
                      email: email,
                      signingOut: _signingOut,
                      onSignOut: _signOut,
                      onForceLogoutAllDevices: _forceLogoutAllDevices,
                      isGoogleLinked: ref.read(authServiceProvider).isGoogleAccountLinked,
                      androidAccessEnabled: androidAccessEnabled,
                      linkingGoogle: _linkingGoogle,
                      onLinkGoogleAccount: _linkGoogleAccount,
                      onUnlinkGoogleAccount: _unlinkGoogleAccount,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInContent extends StatelessWidget {
  const _SignedInContent({
    required this.email,
    required this.signingOut,
    required this.onSignOut,
    required this.onForceLogoutAllDevices,
    required this.isGoogleLinked,
    required this.androidAccessEnabled,
    required this.linkingGoogle,
    required this.onLinkGoogleAccount,
    required this.onUnlinkGoogleAccount,
  });

  final String? email;
  final bool signingOut;
  final VoidCallback onSignOut;
  final VoidCallback onForceLogoutAllDevices;
  final bool isGoogleLinked;
  final bool androidAccessEnabled;
  final bool linkingGoogle;
  final VoidCallback onLinkGoogleAccount;
  final VoidCallback onUnlinkGoogleAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          email ?? '',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        // 안드로이드는 이메일 링크를 받지 않고 Google 로그인만 쓰므로, 이 회사메일
        // 계정으로 안드로이드에서도 같은 데이터를 보려면 여기서 미리 Google 계정을
        // 연동해둬야 한다(웹에서만 가능한 1회성 설정 — sign_in_prompt.dart 참고). 이미
        // 연동된 상태에서 같은 버튼을 다시 누르면 해제로 동작한다(연동/해제 확인
        // 다이얼로그는 AccountDialog가 담당).
        //
        // 관리자가 아직 이 계정에 안드로이드 접근을 안 열어줬으면(androidAccessEnabled
        // false) 섹션 자체를 안 보여준다 — 다만 이미 연동돼 있는 경우(이 필드가 생기기
        // 전에 연동한 계정 등)는 예외로 계속 보여줘서, 해제할 방법이 없어지는 일이 없게 한다.
        if (kIsWeb && (androidAccessEnabled || isGoogleLinked)) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: (linkingGoogle || signingOut)
                  ? null
                  : (isGoogleLinked ? onUnlinkGoogleAccount : onLinkGoogleAccount),
              icon: (linkingGoogle || (isGoogleLinked && signingOut))
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isGoogleLinked ? Icons.link_off : Icons.link),
              label: Text(isGoogleLinked ? 'Google 계정 연동 해제하기' : 'Google 계정 연동하기'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size.fromHeight(48),
              textStyle: TextStyle(
                fontWeight: theme.brightness == Brightness.dark ? FontWeight.w600 : null,
              ),
            ),
            onPressed: signingOut ? null : onSignOut,
            icon: signingOut
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout),
            label: const Text('로그아웃'),
          ),
        ),
        const SizedBox(height: 16),
        // 다른 PC에 로그인한 채로 로그아웃을 잊고 나왔을 때를 위한 안전장치. 자주 쓸
        // 기능이 아니라 위 로그아웃 버튼보다 한 단계 낮은 강조(TextButton)로 둔다.
        TextButton(
          onPressed: signingOut ? null : onForceLogoutAllDevices,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: Text(
            '다른 모든 기기에서 로그아웃',
            style: TextStyle(
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
