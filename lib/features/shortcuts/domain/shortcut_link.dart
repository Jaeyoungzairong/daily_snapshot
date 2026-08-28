import 'package:flutter/material.dart';

class ShortcutLink {
  const ShortcutLink({required this.label, required this.icon, required this.url});

  final String label;
  final IconData icon;
  final String url;
}

const List<ShortcutLink> shortcutLinks = [
  ShortcutLink(label: '그룹웨어', icon: Icons.work, url: 'https://bsp.daouoffice.com/'),
  ShortcutLink(label: 'NAS 서버', icon: Icons.dns, url: 'http://192.168.0.24:3023/'),
  ShortcutLink(label: 'Google', icon: Icons.travel_explore, url: 'https://www.google.com/'),
  ShortcutLink(label: 'Naver', icon: Icons.language, url: 'https://www.naver.com/'),
  ShortcutLink(label: '네이버지도', icon: Icons.map_outlined, url: 'https://map.naver.com/'),
  ShortcutLink(label: '카카오맵', icon: Icons.map, url: 'https://map.kakao.com/'),
  ShortcutLink(label: 'Gmail', icon: Icons.mail, url: 'https://mail.google.com/'),
  ShortcutLink(label: '구글 드라이브', icon: Icons.cloud, url: 'https://drive.google.com/'),
];
