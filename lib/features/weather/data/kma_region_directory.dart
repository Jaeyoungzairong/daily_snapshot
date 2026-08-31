import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import 'city_candidate.dart';

/// 기상청이 공식 배포하는 "동네예보지점좌표" 목록(assets/kma_regions.json, 시/도·시/군/구·
/// 읍/면/동 3,836개 지점)에서 지역을 검색한다. Open-Meteo 지오코딩은 범용 전세계 지명 DB라
/// "판교동", "애월읍", "종로구" 같은 한국 행정구역이 통째로 빠져 있거나 동명이인에 밀려 안
/// 보이는 문제가 있었는데, 기상청이 예보에 쓰는 지점 목록을 그대로 쓰면 그 문제가 없다.
/// 부수 효과로 위경도→격자 변환 없이도(어차피 KmaGrid로 다시 계산하긴 하지만) 기상청이
/// 인정하는 지점만 검색되므로 위경도값 자체의 신뢰도도 더 높다.
class KmaRegionDirectory {
  KmaRegionDirectory.fromRegions(this._regions);

  final List<CityCandidate> _regions;

  static const String _assetPath = 'assets/kma_regions.json';
  static KmaRegionDirectory? _cached;

  static Future<KmaRegionDirectory> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final raw = await rootBundle.loadString(_assetPath);
    final list = (jsonDecode(raw) as List).map((e) {
      final map = e as Map<String, dynamic>;
      return CityCandidate(
        name: map['name'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        admin1: map['admin1'] as String?,
        country: '대한민국',
      );
    }).toList();

    final directory = KmaRegionDirectory.fromRegions(list);
    _cached = directory;
    return directory;
  }

  /// 이름이 검색어와 정확히 일치하는 지점을 최우선으로, 그다음 이름이 검색어로 시작하는
  /// 지점, 그다음 이름/상위 행정구역 어디에든 검색어가 포함되는 지점 순으로 반환한다.
  /// (예: "종로구"로 검색하면 "종로구" 자체가 그 아래 40여 개 동보다 먼저 나온다.)
  List<CityCandidate> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final exact = <CityCandidate>[];
    final startsWith = <CityCandidate>[];
    final contains = <CityCandidate>[];

    for (final region in _regions) {
      if (region.name == trimmed) {
        exact.add(region);
      } else if (region.name.startsWith(trimmed)) {
        startsWith.add(region);
      } else if (region.name.contains(trimmed) || (region.admin1?.contains(trimmed) ?? false)) {
        contains.add(region);
      }
    }

    return [...exact, ...startsWith, ...contains];
  }

  // 기상청 지점 목록이 한국 안에만 있으므로, 최근접 지점과의 거리가 이보다 멀면
  // 한국 밖 좌표(해외 등)로 보고 매칭하지 않는다.
  static const double _maxNearestDistanceKm = 100;

  /// 좌표에서 가장 가까운 지점을 찾는다. 최근접 지점도 [_maxNearestDistanceKm]보다 멀면 null.
  CityCandidate? nearest(double latitude, double longitude) {
    CityCandidate? closest;
    var closestDistanceKm = double.infinity;

    for (final region in _regions) {
      final distanceKm = _distanceKm(latitude, longitude, region.latitude, region.longitude);
      if (distanceKm < closestDistanceKm) {
        closestDistanceKm = distanceKm;
        closest = region;
      }
    }

    if (closest == null || closestDistanceKm > _maxNearestDistanceKm) return null;
    return closest;
  }

  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180);
}
