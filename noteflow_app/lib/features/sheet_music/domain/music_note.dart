/// 單一音符資料
class MusicNote {
  final int midiPitch;
  final double startTime;
  final double endTime;
  final int velocity;
  final int hand; // 0 = right (treble), 1 = left (bass)

  const MusicNote({
    required this.midiPitch,
    required this.startTime,
    required this.endTime,
    this.velocity = 80,
    this.hand = 0,
  });

  double get duration => endTime - startTime;

  /// 音符名稱 (C4, D#5, etc.)
  String get noteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midiPitch ~/ 12) - 1;
    final name = names[midiPitch % 12];
    return '$name$octave';
  }

  /// 相對於中央 C (MIDI 60) 的半音距離
  int get stepsFromMiddleC => midiPitch - 60;

  /// 五線譜上的位置（以半行為單位，中央 C = 0）
  /// 正數向上，負數向下
  int get staffPosition {
    // 將 MIDI pitch 轉為五線譜位置
    // C4=0, D4=1, E4=2, F4=3, G4=4, A4=5, B4=6, C5=7...
    const pitchToPosition = {
      0: 0,  // C
      1: 0,  // C#
      2: 1,  // D
      3: 1,  // D#
      4: 2,  // E
      5: 3,  // F
      6: 3,  // F#
      7: 4,  // G
      8: 4,  // G#
      9: 5,  // A
      10: 5, // A#
      11: 6, // B
    };
    final octave = (midiPitch ~/ 12) - 1;
    final noteInOctave = midiPitch % 12;
    final posInOctave = pitchToPosition[noteInOctave] ?? 0;
    // C4 (octave=4) should be position 0
    return (octave - 4) * 7 + posInOctave;
  }

  /// 是否需要升降記號
  bool get isSharp {
    final noteInOctave = midiPitch % 12;
    return [1, 3, 6, 8, 10].contains(noteInOctave);
  }
}
