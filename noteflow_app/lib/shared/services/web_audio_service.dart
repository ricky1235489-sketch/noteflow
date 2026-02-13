import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web Audio Service using Tone.js with Salamander Grand Piano samples
/// Provides high-quality piano playback via the NoteFlowMidiPlayer JS object
class WebAudioService {
  bool _isReady = false;
  final List<_MidiEvent> _midiEvents = [];

  bool get isReady => _isReady;

  /// Initialize the Tone.js sampler (must be called after user interaction)
  Future<void> initialize() async {
    if (_isReady) return;
    
    try {
      await _initPlayer().toDart;
      _isReady = true;
      print('WebAudioService: Tone.js piano sampler initialized');
    } catch (e) {
      print('WebAudioService: Failed to initialize: $e');
      _isReady = false;
    }
  }

  /// Load MIDI events for playback
  void loadMidiEvents(List<Map<String, dynamic>> events) {
    _midiEvents.clear();
    for (final e in events) {
      _midiEvents.add(_MidiEvent(
        pitch: e['pitch'] as int,
        start: (e['start'] as num).toDouble(),
        duration: (e['duration'] as num).toDouble(),
        velocity: e['velocity'] as int,
      ));
    }
    
    // Convert to JS array and load
    final jsEvents = _midiEvents.map((e) => <String, dynamic>{
      'pitch': e.pitch,
      'start': e.start,
      'duration': e.duration,
      'velocity': e.velocity,
    }.jsify()).toList();
    
    _loadMidi(jsEvents.jsify()!);
  }

  /// Play single MIDI note (for preview/click)
  void playNote({
    required int midiNote,
    int velocity = 80,
    double duration = 0.5,
  }) {
    if (!_isReady) return;
    _playNote(midiNote, velocity, duration);
  }

  /// Stop single MIDI note
  void stopNote({required int midiNote}) {
    // Tone.js sampler handles note release automatically
  }

  /// Stop all notes
  void stopAllNotes() {
    if (!_isReady) return;
    _stop();
  }

  /// Start playback
  void play() {
    if (!_isReady) return;
    _play();
  }

  /// Pause playback
  void pause() {
    if (!_isReady) return;
    _pause();
  }

  /// Stop and reset playback
  void stop() {
    if (!_isReady) return;
    _stop();
  }

  /// Seek to position in seconds
  void seekTo(double seconds) {
    if (!_isReady) return;
    _seekTo(seconds);
  }

  /// Set tempo multiplier (1.0 = normal)
  void setTempo(double multiplier) {
    if (!_isReady) return;
    _setTempo(multiplier);
  }

  /// Get current playback position in seconds
  double getPosition() {
    if (!_isReady) return 0.0;
    return _getPosition();
  }

  /// Check if currently playing
  bool get isPlaying {
    if (!_isReady) return false;
    return _isPlayingJs();
  }

  /// Dispose resources
  void dispose() {
    if (_isReady) {
      _stop();
    }
    _isReady = false;
  }
}

class _MidiEvent {
  final int pitch;
  final double start;
  final double duration;
  final int velocity;

  const _MidiEvent({
    required this.pitch,
    required this.start,
    required this.duration,
    required this.velocity,
  });
}

// JS interop for NoteFlowMidiPlayer
@JS('NoteFlowMidiPlayer.init')
external JSPromise _initPlayer();

@JS('NoteFlowMidiPlayer.loadMidi')
external void _loadMidi(JSAny events);

@JS('NoteFlowMidiPlayer.play')
external void _play();

@JS('NoteFlowMidiPlayer.pause')
external void _pause();

@JS('NoteFlowMidiPlayer.stop')
external void _stop();

@JS('NoteFlowMidiPlayer.seekTo')
external void _seekTo(double seconds);

@JS('NoteFlowMidiPlayer.setTempo')
external void _setTempo(double multiplier);

@JS('NoteFlowMidiPlayer.playNote')
external void _playNote(int midi, int velocity, double duration);

@JS('NoteFlowMidiPlayer.getPosition')
external double _getPosition();

@JS('NoteFlowMidiPlayer.isPlaying')
external bool _isPlayingJs();
