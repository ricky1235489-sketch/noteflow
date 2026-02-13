enum PlaybackStatus { stopped, playing, paused }

class PlaybackState {
  final PlaybackStatus status;
  final Duration currentPosition;
  final Duration totalDuration;
  final double tempoMultiplier;
  final int currentNoteIndex;
  final int currentMeasure;

  const PlaybackState({
    this.status = PlaybackStatus.stopped,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.tempoMultiplier = 1.0,
    this.currentNoteIndex = -1,
    this.currentMeasure = 0,
  });

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? currentPosition,
    Duration? totalDuration,
    double? tempoMultiplier,
    int? currentNoteIndex,
    int? currentMeasure,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      tempoMultiplier: tempoMultiplier ?? this.tempoMultiplier,
      currentNoteIndex: currentNoteIndex ?? this.currentNoteIndex,
      currentMeasure: currentMeasure ?? this.currentMeasure,
    );
  }

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isStopped => status == PlaybackStatus.stopped;

  double get progressPercent {
    if (totalDuration.inMilliseconds == 0) return 0.0;
    return currentPosition.inMilliseconds / totalDuration.inMilliseconds;
  }
}
