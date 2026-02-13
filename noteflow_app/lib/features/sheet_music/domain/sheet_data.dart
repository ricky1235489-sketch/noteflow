import 'music_note.dart';
import 'rest_note.dart';

/// 小節資料
class Measure {
  final int number;
  final List<MusicNote> trebleNotes;
  final List<MusicNote> bassNotes;
  final List<RestNote> trebleRests;
  final List<RestNote> bassRests;
  final double startTime;
  final double endTime;

  const Measure({
    required this.number,
    required this.trebleNotes,
    required this.bassNotes,
    this.trebleRests = const [],
    this.bassRests = const [],
    required this.startTime,
    required this.endTime,
  });
}

/// 完整樂譜資料
class SheetData {
  final List<MusicNote> allNotes;
  final List<Measure> measures;
  final double totalDuration;
  final double tempo;
  final int beatsPerMeasure;
  final int beatUnit; // 拍號分母（4 = 四分音符）
  final int keySignature; // 調號：正數 = 升號數，負數 = 降號數，0 = C 大調

  const SheetData({
    required this.allNotes,
    required this.measures,
    required this.totalDuration,
    this.tempo = 120.0,
    this.beatsPerMeasure = 4,
    this.beatUnit = 4,
    this.keySignature = 0,
  });

  /// 從原始音符列表建立 SheetData
  factory SheetData.fromNotes({
    required List<MusicNote> notes,
    double tempo = 120.0,
    int beatsPerMeasure = 4,
    int beatUnit = 4,
    int keySignature = 0,
  }) {
    if (notes.isEmpty) {
      return SheetData(
        allNotes: const [],
        measures: const [],
        totalDuration: 0,
        tempo: tempo,
        beatsPerMeasure: beatsPerMeasure,
        beatUnit: beatUnit,
        keySignature: keySignature,
      );
    }

    final totalDuration = notes
        .map((n) => n.endTime)
        .reduce((a, b) => a > b ? a : b);

    final secondsPerBeat = 60.0 / tempo;
    final measureDuration = secondsPerBeat * beatsPerMeasure;

    final measureCount = (totalDuration / measureDuration).ceil().clamp(1, 999);

    final measures = List.generate(measureCount, (i) {
      final start = i * measureDuration;
      final end = (i + 1) * measureDuration;

      final measureNotes = notes.where((n) =>
          n.startTime >= start - 0.01 && n.startTime < end).toList();

      final treble = measureNotes.where((n) => n.hand == 0).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      final bass = measureNotes.where((n) => n.hand == 1).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final trebleRests = _computeRests(
        treble, start, end, secondsPerBeat,
      );
      final bassRests = _computeRests(
        bass, start, end, secondsPerBeat,
      );

      return Measure(
        number: i + 1,
        trebleNotes: treble,
        bassNotes: bass,
        trebleRests: trebleRests,
        bassRests: bassRests,
        startTime: start,
        endTime: end,
      );
    });

    return SheetData(
      allNotes: List.unmodifiable(notes),
      measures: List.unmodifiable(measures),
      totalDuration: totalDuration,
      tempo: tempo,
      beatsPerMeasure: beatsPerMeasure,
      beatUnit: beatUnit,
      keySignature: keySignature,
    );
  }

  /// 計算小節內的休止符
  /// 找出音符之間的空隙，產生對應的休止符
  static List<RestNote> _computeRests(
    List<MusicNote> notes,
    double measureStart,
    double measureEnd,
    double secondsPerBeat,
  ) {
    // 整個小節都沒有音符 → 全休止符
    if (notes.isEmpty) {
      final durationBeats = (measureEnd - measureStart) / secondsPerBeat;
      return [
        RestNote.fromBeats(
          startTime: measureStart,
          durationInBeats: durationBeats,
        ),
      ];
    }

    final rests = <RestNote>[];
    const minRestBeats = 0.2; // 忽略太短的空隙

    // 小節開頭到第一個音符之間的空隙
    final firstNoteStart = notes.first.startTime;
    final leadingGap = (firstNoteStart - measureStart) / secondsPerBeat;
    if (leadingGap > minRestBeats) {
      rests.add(RestNote.fromBeats(
        startTime: measureStart,
        durationInBeats: leadingGap,
      ));
    }

    // 音符之間的空隙
    for (var i = 0; i < notes.length - 1; i++) {
      final currentEnd = notes[i].endTime;
      final nextStart = notes[i + 1].startTime;
      final gapBeats = (nextStart - currentEnd) / secondsPerBeat;
      if (gapBeats > minRestBeats) {
        rests.add(RestNote.fromBeats(
          startTime: currentEnd,
          durationInBeats: gapBeats,
        ));
      }
    }

    // 最後一個音符到小節結尾的空隙
    final lastNoteEnd = notes.last.endTime;
    final trailingGap = (measureEnd - lastNoteEnd) / secondsPerBeat;
    if (trailingGap > minRestBeats) {
      rests.add(RestNote.fromBeats(
        startTime: lastNoteEnd,
        durationInBeats: trailingGap,
      ));
    }

    return rests;
  }
}
