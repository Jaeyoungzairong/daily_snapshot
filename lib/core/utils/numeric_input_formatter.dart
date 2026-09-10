import 'package:flutter/services.dart';

/// 숫자/소수점 외 문자(한글, 영문 등)를 걸러내고, 소수점은 하나만 허용한다. 단, IME가
/// 조합 중인 동안(composing)은 손대지 않는다 — 조합 중에 텍스트를 수정하면 이미 확정된
/// 문자까지 같이 사라지는 문제가 한글 입력에서 확인되었다.
class NumericInputFormatter extends TextInputFormatter {
  static final RegExp _allowed = RegExp(r'[0-9.]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.composing.isValid) return newValue;

    final text = newValue.text;
    final buffer = StringBuffer();
    var newOffset = 0;
    var hasDot = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (!_allowed.hasMatch(char)) continue;
      if (char == '.' && hasDot) continue; // 소수점은 하나만 허용
      if (char == '.') hasDot = true;
      buffer.write(char);
      if (i < newValue.selection.end) newOffset++;
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
