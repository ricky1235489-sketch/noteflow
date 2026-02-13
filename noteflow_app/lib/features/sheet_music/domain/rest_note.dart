/// 休止符類型
enum RestType {
  whole,    // 全休止符
  half,     // 二分休止符
  quarter,  // 四分休止符
  eighth,   // 八分休止符
  sixteenth, // 十六分休止符
}

/// 休止符資料
class RestNote {
  final double startTime;
  final double duration;
  final RestType type;

  const RestNote({
    required this.startTime,
    required this.duration,
    required this.type,
  });

  /// 根據拍數自動判斷休止符類型
  factory RestNote.fromBeats({
    required double startTime,
    required double durationInBeats,
  }) {
    final RestType type;
    if (durationInBeats >= 3.5) {
      type = RestType.whole;
    } else if (durationInBeats >= 1.75) {
      type = RestType.half;
    } else if (durationInBeats >= 0.875) {
      type = RestType.quarter;
    } else if (durationInBeats >= 0.4375) {
      type = RestType.eighth;
    } else {
      type = RestType.sixteenth;
    }

    return RestNote(
      startTime: startTime,
      duration: durationInBeats,
      type: type,
    );
  }
}
