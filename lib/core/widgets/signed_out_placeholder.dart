import 'package:flutter/material.dart';

/// 로그인이 필요한 카드에서 공통으로 보여주는 안내. 로그인/로그아웃은 이 카드가 아니라
/// 화면 우측 상단 계정 아이콘에서 진행한다.
class SignedOutPlaceholder extends StatelessWidget {
  const SignedOutPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        '우측 상단 계정 아이콘에서 로그인 후 이용할 수 있습니다.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}
