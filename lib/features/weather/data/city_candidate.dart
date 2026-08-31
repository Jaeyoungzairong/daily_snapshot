class CityCandidate {
  const CityCandidate({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.admin1,
    this.country,
    this.population,
  });

  factory CityCandidate.fromJson(Map<String, dynamic> json) {
    return CityCandidate(
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      admin1: json['admin1'] as String?,
      country: json['country'] as String?,
      population: (json['population'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      if (admin1 != null) 'admin1': admin1,
      if (country != null) 'country': country,
    };
  }

  final String name;
  final double latitude;
  final double longitude;
  final String? admin1;
  final String? country;

  /// 동명 지명 후보 중 "진짜 잘 알려진 도시"를 가려내기 위한 인구수.
  /// Open-Meteo 지오코딩 데이터에서 마을 단위의 무명 지명은 이 필드가 비어있는 경우가 많아,
  /// 값이 있는 후보를 우선 정렬하는 데 사용한다.
  final int? population;

  /// 검색 결과 후보를 사람이 구분할 수 있게 보여주기 위한 라벨.
  /// 동명 지명(예: "Anyang"이 여러 나라에 존재)을 지역/국가로 구분하기 위해 사용한다.
  String get displayLabel {
    final parts = [name, ?admin1, ?country];
    return parts.join(', ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CityCandidate &&
          other.name == name &&
          other.latitude == latitude &&
          other.longitude == longitude);

  @override
  int get hashCode => Object.hash(name, latitude, longitude);
}
