import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/midi_playback_service.dart';
import '../../../shared/services/web_audio_service.dart';
import '../../sheet_music/domain/sheet_data.dart';
import '../data/playback_scheduler.dart';
import '../domain/playback_state.dart';

/// 全域 MidiPlaybackService provider
final midiPlaybackServiceProvider = Provider<MidiPlaybackService>((ref) {
  final service = MidiPlaybackService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 全域 WebAudioService provider
final webAudioServiceProvider = Provider<WebAudioService>((ref) {
  final service = WebAudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackState>((ref) {
  final audioService = ref.watch(webAudioServiceProvider);
  return PlaybackNotifier(audioService: audioService);
});

class PlaybackNotifier extends StateNotifier<PlaybackState> {
  final WebAudioService _audioService;
  PlaybackScheduler? _scheduler;
  SheetData? _currentSheetData;
  bool _isDisposed = false;

  PlaybackNotifier({required WebAudioService audioService})
      : _audioService = audioService,
        super(const PlaybackState());

  /// 載入樂譜資料並建立排程器
  Future<void> loadSheetData(SheetData sheetData) async {
    // 確保 AudioContext 已初始化
    if (!_audioService.isReady) {
      await _audioService.initialize();
    }

    _scheduler?.dispose();
    _currentSheetData = sheetData;

    // Load MIDI events into Tone.js player
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

    _scheduler = PlaybackScheduler(
      audioService: _audioService,
      sheetData: sheetData,
      onPositionChanged: _onPositionChanged,
      onCompleted: _onCompleted,
    );

    final totalMs = (sheetData.totalDuration * 1000).round();
    state = state.copyWith(
      status: PlaybackStatus.stopped,
      totalDuration: Duration(milliseconds: totalMs),
      currentPosition: Duration.zero,
      currentNoteIndex: -1,
      currentMeasure: 0,
    );
  }

  void play() {
    final scheduler = _scheduler;
    if (scheduler == null || _isDisposed) return;

    state = state.copyWith(status: PlaybackStatus.playing);
    scheduler.play();
  }

  void pause() {
    if (_isDisposed) return;
    _scheduler?.pause();
    state = state.copyWith(status: PlaybackStatus.paused);
  }

  void stop() {
    // Stop scheduler first to cancel timers
    _scheduler?.stop();
    // Only update state if not disposed
    if (!_isDisposed) {
      state = state.copyWith(
        status: PlaybackStatus.stopped,
        currentPosition: Duration.zero,
        currentNoteIndex: -1,
        currentMeasure: 0,
      );
    }
  }

  /// Stop playback without updating state (for cleanup during disposal)
  void stopSilently() {
    _scheduler?.stop();
  }

  void seekTo(Duration position) {
    if (_isDisposed) return;
    _scheduler?.seekTo(position);
    state = state.copyWith(currentPosition: position);
  }

  void setTempo(double multiplier) {
    if (_isDisposed) return;
    final clamped = multiplier.clamp(
      AppConstants.minTempoMultiplier,
      AppConstants.maxTempoMultiplier,
    );
    _scheduler?.setTempo(clamped);
    state = state.copyWith(tempoMultiplier: clamped);
  }

  /// 點擊小節跳轉
  void seekToMeasure(int measureIndex, SheetData sheetData) {
    if (measureIndex < 0 || measureIndex >= sheetData.measures.length) return;

    final measure = sheetData.measures[measureIndex];
    final positionMs = (measure.startTime * 1000).round();
    seekTo(Duration(milliseconds: positionMs));
  }

  void _onPositionChanged(Duration position, int noteIndex, int measure) {
    if (_isDisposed) return;
    state = state.copyWith(
      currentPosition: position,
      currentNoteIndex: noteIndex,
      currentMeasure: measure,
    );
  }

  void _onCompleted() {
    if (_isDisposed) return;
    state = state.copyWith(
      status: PlaybackStatus.stopped,
      currentPosition: Duration.zero,
      currentNoteIndex: -1,
      currentMeasure: 0,
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Stop playback silently without state updates
    _scheduler?.stop();
    _scheduler?.dispose();
    _scheduler = null;
    super.dispose();
  }
}
