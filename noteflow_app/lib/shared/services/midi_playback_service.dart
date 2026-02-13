import 'web_audio_service.dart';

/// MIDI 合成播放服務（抽象層）
/// Web 平台使用 WebAudioService 合成鋼琴音色
class MidiPlaybackService {
  final WebAudioService _webAudio = WebAudioService();

  bool get isReady => _webAudio.isReady;

  /// 初始化音訊引擎（需在使用者互動後呼叫）
  Future<void> initialize() async {
    if (_webAudio.isReady) return;
    await _webAudio.initialize();
  }

  /// 播放單一 MIDI 音符
  void playNote({
    required int midiNote,
    int velocity = 80,
  }) {
    _webAudio.playNote(midiNote: midiNote, velocity: velocity);
  }

  /// 停止單一 MIDI 音符
  void stopNote({required int midiNote}) {
    _webAudio.stopNote(midiNote: midiNote);
  }

  /// 停止所有音符
  void stopAllNotes() {
    _webAudio.stopAllNotes();
  }

  /// 釋放資源
  void dispose() {
    _webAudio.dispose();
  }
}
