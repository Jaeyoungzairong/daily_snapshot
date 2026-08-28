/// 기상청 API의 base_date/base_time 계산.
class KmaBaseTime {
  KmaBaseTime._();

  /// 초단기실황(getUltraSrtNcst)용 base_date/base_time.
  /// 정시 관측자료는 매시 40분경 확정되어 제공되므로, 아직 40분이 지나지 않았다면
  /// 한 시간 전 관측자료를 요청한다.
  static ({String baseDate, String baseTime}) ultraSrtNcst(DateTime now) {
    final target = now.minute < 40 ? now.subtract(const Duration(hours: 1)) : now;
    return (baseDate: _formatDate(target), baseTime: '${_two(target.hour)}00');
  }

  /// 단기예보(getVilageFcst)용 base_date/base_time.
  /// 02/05/08/11/14/17/20/23시에 생성되고 생성 후 약 10분 뒤부터 제공되므로,
  /// 그 기준으로 이미 발표가 끝났다고 볼 수 있는 가장 최근 시각을 고른다.
  static ({String baseDate, String baseTime}) vilageFcst(DateTime now) {
    const slots = [23, 20, 17, 14, 11, 8, 5, 2];
    final safeNow = now.subtract(const Duration(minutes: 10));
    for (final hour in slots) {
      if (safeNow.hour >= hour) {
        return (baseDate: _formatDate(safeNow), baseTime: '${_two(hour)}00');
      }
    }
    // safeNow가 새벽 2시 이전 → 아직 오늘 첫 발표(02시) 전이므로 전날 23시 발표분을 쓴다.
    final prevDay = DateTime(safeNow.year, safeNow.month, safeNow.day).subtract(const Duration(days: 1));
    return (baseDate: _formatDate(prevDay), baseTime: '2300');
  }

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}
