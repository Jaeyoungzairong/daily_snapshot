import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      await ref.read(authServiceProvider).signOut();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그아웃에 실패했습니다. 다시 시도해주세요.')),
        );
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

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(32, 36, 32, 36),
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
            const SizedBox(height: 20),
            authState.when(
              loading: () => const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text('로그인 상태를 확인할 수 없습니다: $error'),
              data: (uid) => uid == null
                  ? const SignInPrompt()
                  : _SignedInContent(email: email, signingOut: _signingOut, onSignOut: _signOut),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignedInContent extends StatelessWidget {
  const _SignedInContent({required this.email, required this.signingOut, required this.onSignOut});

  final String? email;
  final bool signingOut;
  final VoidCallback onSignOut;

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
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              minimumSize: const Size.fromHeight(52),
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
      ],
    );
  }
}
