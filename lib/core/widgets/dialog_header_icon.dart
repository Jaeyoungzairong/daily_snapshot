import 'package:flutter/material.dart';

/// 다이얼로그 상단에 시각적 앵커를 주는 원형 아이콘. 계정 다이얼로그(파란 계열)와
/// 삭제 확인 다이얼로그(빨간 계열)처럼 맥락에 따라 색만 다르게 써서 공용으로 둔다.
class DialogHeaderIcon extends StatelessWidget {
  const DialogHeaderIcon({
    super.key,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Icon(icon, color: foregroundColor, size: 28),
    );
  }
}
