/// 播放排程用的音符事件
class PlaybackEvent {
  final int noteIndex;
  final int midiPitch;
  final int velocity;
  final double startTimeSec;
  final double endTimeSec;
  final int measureIndex;

  const PlaybackEvent({
    required this.noteIndex,
    required this.midiPitch,
    required this.velocity,
    required this.startTimeSec,
    required this.endTimeSec,
    required this.measureIndex,
  });

  /// 套用速度倍率後的開始時間
  double scaledStartTime(double tempoMultiplier) =>
      startTimeSec / tempoMultiplier;

  /// 套用速度倍率後的結束時間
  double scaledEndTime(double tempoMultiplier) =>
      endTimeSec / tempoMultiplier;
}
