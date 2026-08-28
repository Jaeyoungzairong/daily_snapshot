import 'package:flutter/material.dart';

class ShortcutLink {
  const ShortcutLink({required this.label, required this.icon, required this.url});

  final String label;
  final IconData icon;
  final String url;
}

const List<ShortcutLink> shortcutLinks = [
  ShortcutLink(label: '그룹웨어', icon: Icons.business, url: 'https://bsp.daouoffice.com/'),
  ShortcutLink(label: 'NAS 서버', icon: Icons.dns, url: 'http://192.168.0.24:3023/'),
  ShortcutLink(label: 'Google', icon: Icons.search, url: 'https://www.google.com/'),
  ShortcutLink(label: 'Naver', icon: Icons.public, url: 'https://www.naver.com/'),
  ShortcutLink(label: '네이버 지도', icon: Icons.map_outlined, url: 'https://map.naver.com/'),
  ShortcutLink(label: 'Gmail', icon: Icons.mail_outline, url: 'https://mail.google.com/'),
  ShortcutLink(label: '구글 드라이브', icon: Icons.cloud_outlined, url: 'https://drive.google.com/'),
];
