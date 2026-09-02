// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// 로그인 링크 처리 후 주소창에 남는 oobCode 등의 쿼리를 지운다 — 새로고침 시 같은
/// 링크가 다시 처리되는 것을 막기 위함.
void clearSignInLinkFromUrl() {
  html.window.history.replaceState(null, '', html.window.location.pathname);
}
