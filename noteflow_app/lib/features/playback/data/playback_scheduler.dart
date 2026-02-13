import 'dart:async';
import '../domain/playback_event.dart';
import '../../../shared/services/web_audio_service.dart';
import '../../sheet_music/domain/music_note.dart';
import '../../sheet_music/domain/sheet_data.dart';

/// 播放位置回呼
typedef PositionCallback = void Function(
  Duration position,
  int noteIndex,
  int measureIndex,
);

/// 播放結束回呼
typedef CompletionCallback = void Function();

/// 播放排程器
/// 使用 Tone.js 進行高品質鋼琴音色播放
class PlaybackScheduler {
  final WebAudioService _audioService;
  final List<PlaybackEvent> _events;
  final double _totalDurationSec;
  final PositionCallback onPositionChanged;
  final CompletionCallback onCompleted;

  double _tempoMultiplier = 1.0;
  double _currentTimeSec = 0.0;
  Timer? _positionTimer;
  bool _isPlaying = false;

  static const _tickIntervalMs = 50; // Position update interval

  PlaybackScheduler({
    required WebAudioService audioService,
    required SheetData sheetData,
    required this.onPositionChanged,
    required this.onCompleted,
  })  : _audioService = audioService,
        _events = _buildEvents(sheetData),
        _totalDurationSec = sheetData.totalDuration {
    // Load MIDI events into Tone.js player
    _loadMidiEvents(sheetData);
  }

  double get totalDurationSec => _totalDurationSec;
  double get currentTimeSec => _currentTimeSec;

  /// 從 SheetData 建立排程事件列表
  static List<PlaybackEvent> _buildEvents(SheetData sheetData) {
    final events = <PlaybackEvent>[];

    for (var mi = 0; mi < sheetData.measures.length; mi++) {
      final measure = sheetData.measures[mi];
      final allNotesInMeasure = [
        ...measure.trebleNotes,
        ...measure.bassNotes,
      ];

      for (final note in allNotesInMeasure) {
        final noteIndex = sheetData.allNotes.indexOf(note);
        events.add(PlaybackEvent(
          noteIndex: noteIndex,
          midiPitch: note.midiPitch,
          velocity: note.velocity,
          startTimeSec: note.startTime,
          endTimeSec: note.endTime,
          measureIndex: mi,
        ));
      }
    }

    events.sort((a, b) => a.startTimeSec.compareTo(b.startTimeSec));
    return events;
  }

  /// Load MIDI events into Tone.js player
  void _loadMidiEvents(SheetData sheetData) {
    final midiEvents = <Map<String, dynamic>>[];
    
    for (final note in sheetData.allNotes) {
      midiEvents.add({
        'pitch': note.midiPitch,
        'start': note.startTime,
        'duration': note.endTime - note.startTime,
        'velocity': note.velocity,
      });
    }
    
    _audioService.loadMidiEvents(midiEvents);
  }

  /// 開始播放
  void play() {
    _isPlaying = true;
    _audioService.play();
    _startPositionTimer();
  }

  /// 暫停播放
  void pause() {
    _isPlaying = false;
    _audioService.pause();
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// 停止播放並重置
  void stop() {
    _isPlaying = false;
    _positionTimer?.cancel();
    _positionTimer = null;
    _audioService.stop();
    _currentTimeSec = 0.0;
  }

  /// 跳轉到指定位置
  void seekTo(Duration position) {
    _currentTimeSec = position.inMilliseconds / 1000.0;
    _audioService.seekTo(_currentTimeSec);
  }

  /// 設定速度倍率
  void setTempo(double multiplier) {
    _tempoMultiplier = multiplier;
    _audioService.setTempo(multiplier);
  }

  /// Start position tracking timer
  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(
      const Duration(milliseconds: _tickIntervalMs),
      (_) => _updatePosition(),
    );
  }

  /// Update position and notify listeners
  void _updatePosition() {
    if (!_isPlaying) return;
    
    _currentTimeSec = _audioService.getPosition();
    
    final scaledTotal = _totalDurationSec / _tempoMultiplier;

    // 播放結束
    if (_currentTimeSec >= scaledTotal) {
      stop();
      onCompleted();
      return;
    }

    // Find the most recent active note and its measure for highlighting.
    // We scan all events and pick the latest one whose scaled start time
    // has been reached, so the cursor stays on the correct note/measure
    // even when notes overlap or are dense.
    var currentNoteIndex = -1;
    var currentMeasure = 0;
    var bestStartTime = -1.0;

    for (final event in _events) {
      final scaledStart = event.scaledStartTime(_tempoMultiplier);
      final scaledEnd = event.scaledEndTime(_tempoMultiplier);

      if (_currentTimeSec >= scaledStart && _currentTimeSec < scaledEnd) {
        // Among overlapping notes, prefer the one that started most recently
        if (scaledStart > bestStartTime) {
          bestStartTime = scaledStart;
          currentNoteIndex = event.noteIndex;
          currentMeasure = event.measureIndex;
        }
      }
    }

    // If no active note found, find the measure by time position
    if (currentNoteIndex < 0 && _events.isNotEmpty) {
      for (final event in _events.reversed) {
        if (_currentTimeSec >= event.scaledStartTime(_tempoMultiplier)) {
          currentMeasure = event.measureIndex;
          break;
        }
      }
    }

    final positionMs = (_currentTimeSec * 1000).round();
    onPositionChanged(
      Duration(milliseconds: positionMs),
      currentNoteIndex,
      currentMeasure,
    );
  }

  /// 釋放資源
  void dispose() {
    stop();
  }
}
