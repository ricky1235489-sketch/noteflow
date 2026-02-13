import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Recording state
enum RecordingStatus { idle, recording, paused, stopped }

class RecordingState {
  final RecordingStatus status;
  final Duration elapsed;
  final String? errorMessage;
  final Uint8List? recordedBytes;
  final String? fileName;

  const RecordingState({
    this.status = RecordingStatus.idle,
    this.elapsed = Duration.zero,
    this.errorMessage,
    this.recordedBytes,
    this.fileName,
  });

  RecordingState copyWith({
    RecordingStatus? status,
    Duration? elapsed,
    String? errorMessage,
    Uint8List? recordedBytes,
    String? fileName,
  }) {
    return RecordingState(
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      errorMessage: errorMessage ?? this.errorMessage,
      recordedBytes: recordedBytes ?? this.recordedBytes,
      fileName: fileName ?? this.fileName,
    );
  }

  bool get isRecording => status == RecordingStatus.recording;
  bool get hasRecording =>
      status == RecordingStatus.stopped && recordedBytes != null;
}

/// Platform-agnostic audio recorder.
///
/// On web: uses MediaRecorder API via dart:js_interop.
/// On mobile: uses the `record` package (when enabled).
class AudioRecorderService {
  AudioRecorderService();

  Timer? _timer;
  DateTime? _startTime;
  final _stateController = StreamController<RecordingState>.broadcast();
  RecordingState _state = const RecordingState();

  Stream<RecordingState> get stateStream => _stateController.stream;
  RecordingState get currentState => _state;

  void _emit(RecordingState s) {
    _state = s;
    _stateController.add(s);
  }

  /// Check if recording is supported on this platform.
  Future<bool> isSupported() async {
    if (kIsWeb) return true; // MediaRecorder is widely supported
    return true; // Mobile: record package handles this
  }

  /// Start recording audio.
  Future<void> startRecording() async {
    if (_state.isRecording) return;

    try {
      if (kIsWeb) {
        await _startWebRecording();
      } else {
        await _startMobileRecording();
      }

      _startTime = DateTime.now();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_startTime != null) {
          final elapsed = DateTime.now().difference(_startTime!);
          _emit(_state.copyWith(elapsed: elapsed));
        }
      });

      _emit(_state.copyWith(status: RecordingStatus.recording));
    } catch (e) {
      _emit(RecordingState(
        status: RecordingStatus.idle,
        errorMessage: '無法啟動錄音: $e',
      ));
    }
  }

  /// Stop recording and return the audio bytes.
  Future<RecordingState> stopRecording() async {
    _timer?.cancel();
    _timer = null;

    try {
      Uint8List? bytes;
      if (kIsWeb) {
        bytes = await _stopWebRecording();
      } else {
        bytes = await _stopMobileRecording();
      }

      final now = DateTime.now();
      final fileName =
          'recording_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}.wav';

      final result = RecordingState(
        status: RecordingStatus.stopped,
        elapsed: _state.elapsed,
        recordedBytes: bytes,
        fileName: fileName,
      );
      _emit(result);
      return result;
    } catch (e) {
      final result = RecordingState(
        status: RecordingStatus.idle,
        errorMessage: '錄音停止失敗: $e',
      );
      _emit(result);
      return result;
    }
  }

  /// Reset to idle state.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _startTime = null;
    _emit(const RecordingState());
  }

  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }

  // ── Web implementation (MediaRecorder) ──────────────────

  // Web recording state stored as JS interop handles
  dynamic _mediaRecorder;
  List<dynamic> _audioChunks = [];
  Completer<Uint8List>? _stopCompleter;

  Future<void> _startWebRecording() async {
    // Web recording is handled via JS interop in the web entrypoint.
    // For now, we use a simplified approach that works with dart:html on web.
    if (!kIsWeb) return;

    // The actual web implementation uses JS interop — see web_recorder_stub.dart
    // This is a placeholder that will be replaced by conditional imports.
    _audioChunks = [];
  }

  Future<Uint8List?> _stopWebRecording() async {
    if (!kIsWeb) return null;
    // Return placeholder — real implementation via JS interop
    return null;
  }

  // ── Mobile implementation (record package) ──────────────

  Future<void> _startMobileRecording() async {
    // Uses the `record` package when targeting mobile.
    // Currently commented out in pubspec.yaml.
    // When enabled:
    // final recorder = AudioRecorder();
    // await recorder.start(const RecordConfig(), path: tempPath);
  }

  Future<Uint8List?> _stopMobileRecording() async {
    return null;
  }
}
