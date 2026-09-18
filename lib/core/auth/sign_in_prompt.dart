import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../utils/web_url.dart';
import '../widgets/loading_error_view.dart';
import 'auth_provider.dart';
import 'auth_service.dart';

/// 로그인 링크 처리 중 발생한 예외를 사용자에게 보여줄 한국어 메시지로 바꾼다.
String describeAuthError(Object error) {
  if (error is NotApprovedException) {
    return '관리자 승인이 필요한 이메일입니다. 관리자에게 계정 추가를 요청해주세요.';
  }
  if (error is PendingEmailNotFoundException) {
    return '로그인을 요청했던 기기(브라우저)에서 다시 열어주세요.';
  }
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-action-code':
        return '유효하지 않거나 이미 사용된 링크입니다. 입력한 이메일이 맞는지 확인하거나, 새 로그인 링크를 다시 요청해주세요.';
      case 'expired-action-code':
        return '로그인 링크가 만료되었습니다. 새 로그인 링크를 다시 요청해주세요.';
      case 'invalid-email':
        return '이메일 형식을 다시 확인해주세요.';
      case 'credential-already-in-use':
        return '이 Google 계정은 이미 다른 계정에 연동되어 있습니다.';
      case 'provider-already-linked':
        return '이미 이 계정에 Google 계정이 연동되어 있습니다.';
    }
  }
  if (error is GoogleSignInException) {
    return 'Google 로그인 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
  }
  return '로그인 처리 중 문제가 발생했습니다: $error';
}

class SignInPrompt extends ConsumerStatefulWidget {
  const SignInPrompt({super.key});

  @override
  ConsumerState<SignInPrompt> createState() => _SignInPromptState();
}

class _SignInPromptState extends ConsumerState<SignInPrompt> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _manualEmailController = TextEditingController();
  bool _sending = false;
  bool _linkSent = false;
  String? _errorMessage;

  // 이메일 링크로 돌아온 경우를 위한 상태(웹 전용 — 안드로이드는 Google 로그인만 쓰므로
  // 이 상태들이 전혀 필요 없다). isSignInWithEmailLink()/저장된 이메일 조회는 로컬
  // 확인일 뿐 Firebase 서버 호출이 아니므로 자동으로 미리 보여줘도 안전하다. 실제
  // 로그인(signInWithEmailLink, 서버 호출)은 사용자가 "로그인 계속하기"를 직접 눌러야만
  // 실행된다 — 그래야 메일 보안 스캐너가 링크를 미리 열어봐도 1회용 로그인 코드가 그
  // 자리에서 소모되지 않는다.
  bool _checkingLink = kIsWeb;
  bool _isLinkMode = false;
  bool _confirming = false;
  String? _pendingEmail;
  // _checkForSignInLink()에서 감지한 링크를 그대로 저장해뒀다가 _confirmSignIn()에서
  // 재사용한다 — 다시 조회하지 않고 최초에 확인한 값을 그대로 써야 안전하다.
  String? _detectedLink;

  bool _signingInWithGoogle = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _checkForSignInLink();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _manualEmailController.dispose();
    super.dispose();
  }

  Future<void> _checkForSignInLink() async {
    final authService = ref.read(authServiceProvider);
    final link = Uri.base.toString();
    if (!mounted) return;
    if (!authService.isSignInLink(link)) {
      setState(() => _checkingLink = false);
      return;
    }
    _detectedLink = link;
    final email = await authService.peekPendingEmail();
    if (!mounted) return;
    setState(() {
      _checkingLink = false;
      _isLinkMode = true;
      _pendingEmail = email;
    });
  }

  // 이 브라우저에 저장된 이메일이 없으면(다른 기기에서 링크를 열었거나, 관리자가
  // 발송 한도를 우회하려고 직접 생성한 링크를 열었을 때) 사용자가 입력한 이메일을 쓴다.
  Future<void> _confirmSignIn() async {
    if (_confirming) return;
    String? manualEmail;
    if (_pendingEmail == null) {
      manualEmail = _manualEmailController.text.trim();
      if (manualEmail.isEmpty) return;
    }
    setState(() {
      _confirming = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .completeSignInIfLink(_detectedLink!, emailOverride: manualEmail);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLinkMode = false;
        _errorMessage = describeAuthError(error);
      });
    } finally {
      clearSignInLinkFromUrl();
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _sendLink() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).sendSignInLink(email);
      if (!mounted) return;
      setState(() => _linkSent = true);
    } on NotApprovedException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = describeAuthError(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '로그인 링크 발송에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_signingInWithGoogle) return;
    setState(() {
      _signingInWithGoogle = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on GoogleSignInException catch (error) {
      // 계정 선택 화면에서 사용자가 직접 취소한 경우는 에러가 아니라 정상적인
      // 흐름이라 메시지를 띄우지 않는다.
      if (mounted && error.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _errorMessage = describeAuthError(error));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = describeAuthError(error));
    } finally {
      if (mounted) setState(() => _signingInWithGoogle = false);
    }
  }

  /// 앱 전역 인풋 테마(아웃라인 테두리)를 이 다이얼로그 안에서만 채워진(filled) 스타일로
  /// 바꿔서 좀 더 현대적인 느낌을 준다. 다른 화면의 입력창에는 영향을 주지 않는다.
  InputDecoration _emailDecoration(ThemeData theme, String label) {
    // 라이트 모드에서는 surfaceContainerHighest가 다이얼로그 배경과 톤 차이가 거의 없어
    // 테두리 없이는 입력창 경계가 잘 안 보인다 — outlineVariant로 옅은 테두리를 둬서
    // 라이트/다크 모두에서 경계가 드러나게 한다.
    final borderSide = BorderSide(color: theme.colorScheme.outlineVariant);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: borderSide),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: borderSide,
      ),
    );
  }

  /// 다이얼로그 버튼들의 기본 모양(스타디움/알약 형태)이 폭이 넓은 버튼에서는
  /// 비율이 어색해 보여, 입력창과 같은 둥근 사각형(radius 12)으로 통일하고,
  /// 기본 높이(40)보다 좀 더 키워서 존재감을 준다. 다크모드는 밝은 배경 위 어두운
  /// 글자라 얇아 보이는 착시가 있어 SemiBold로 보정하고, 라이트모드는 이미 진한 배경
  /// 위 흰 글자라 또렷해서 기본 굵기(Regular)를 그대로 쓴다.
  ButtonStyle _buttonShape(ThemeData theme) => FilledButton.styleFrom(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    minimumSize: const Size.fromHeight(48),
    textStyle: TextStyle(fontWeight: theme.brightness == Brightness.dark ? FontWeight.w600 : null),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 안드로이드는 이메일 링크를 아예 받지 않고 Google 로그인만 쓴다 — 회사 메일 앱이
    // 링크를 가로채 App Links가 못 열리는 문제를 원천적으로 피하기 위함. 이 계정으로
    // 할일/메모 데이터를 이어서 보려면 웹에서 미리 계정 연동(AccountDialog의
    // "Google 계정 연동하기")을 해둬야 한다.
    if (!kIsWeb) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '로그인하면 할 일·메모·파일함을 이용할 수 있어요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: _buttonShape(theme),
              onPressed: _signingInWithGoogle ? null : _signInWithGoogle,
              icon: _signingInWithGoogle
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Google로 로그인'),
            ),
          ),
        ],
      );
    }

    if (_checkingLink) {
      return const SizedBox(height: 60, child: LoadingView());
    }

    if (_isLinkMode) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _pendingEmail != null
                ? '$_pendingEmail 계정으로 로그인하시겠습니까?'
                : '이 브라우저에서 로그인 요청 정보를 찾을 수 없습니다.\n로그인 링크를 요청했던 이메일을 입력해주세요.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (_pendingEmail == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _manualEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _emailDecoration(theme, '이메일'),
              onSubmitted: (_) => _confirmSignIn(),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: _buttonShape(theme),
              onPressed: _confirming ? null : _confirmSignIn,
              child: _confirming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('로그인 계속하기'),
            ),
          ),
        ],
      );
    }

    if (_linkSent) {
      return Text(
        '입력하신 이메일로 로그인 링크를 보냈습니다.\n메일함에서 링크를 확인해주세요.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '로그인하면 할 일·메모·파일함을 이용할 수 있어요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _emailDecoration(theme, '이메일'),
          onSubmitted: (_) => _sendLink(),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: _buttonShape(theme),
            onPressed: _sending ? null : _sendLink,
            child: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('로그인 링크 받기'),
          ),
        ),
      ],
    );
  }
}
