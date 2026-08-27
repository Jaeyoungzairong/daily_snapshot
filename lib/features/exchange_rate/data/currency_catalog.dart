class CurrencyInfo {
  const CurrencyInfo({
    required this.code,
    required this.displayName,
    this.unit = 1,
  });

  /// ISO 4217 통화 코드 (예: USD, CNY, JPY)
  final String code;
  final String displayName;

  /// 표시 단위. 엔화처럼 1단위 금액이 너무 작아 관례적으로 100엔당 환율을 쓰는 통화를 위한 값.
  final int unit;
}

class CurrencyCatalog {
  CurrencyCatalog._();

  /// 원화(KRW) 대비로 보여줄 통화 목록.
  /// 통화를 추가/제거하려면 이 목록만 수정하면 되고, 최신 환율 표시와 그래프 모두에 자동 반영된다.
  static const List<CurrencyInfo> targetCurrencies = [
    CurrencyInfo(code: 'USD', displayName: '미국 달러'),
    CurrencyInfo(code: 'CNY', displayName: '중국 위안'),
    CurrencyInfo(code: 'JPY', displayName: '일본 엔', unit: 100),
  ];

  static CurrencyInfo byCode(String code) {
    return targetCurrencies.firstWhere((c) => c.code == code);
  }
}
