import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/audio_recorder_service.dart';
import 'transcription_provider.dart';

final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final service = AudioRecorderService();
  ref.onDispose(() => service.dispose());
  return service;
});

final recordingStateProvider =
    StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
  final recorder = ref.watch(audioRecorderProvider);
  return RecordingNotifier(recorder: recorder);
});

class RecordingNotifier extends StateNotifier<RecordingState> {
  final AudioRecorderService _recorder;
  StreamSubscription<RecordingState>? _sub;

  RecordingNotifier({required AudioRecorderService recorder})
      : _recorder = recorder,
        super(const RecordingState()) {
    _sub = _recorder.stateStream.listen((s) {
      if (mounted) state = s;
    });
  }

  Future<void> startRecording() async {
    await _recorder.startRecording();
  }

  Future<void> stopAndUpload(UploadNotifier uploadNotifier) async {
    final result = await _recorder.stopRecording();
    if (result.hasRecording && result.recordedBytes != null) {
      await uploadNotifier.uploadRecordedAudio(
        fileBytes: result.recordedBytes!,
        fileName: result.fileName ?? 'recording.wav',
      );
    }
    _recorder.reset();
  }

  void cancel() {
    _recorder.reset();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
