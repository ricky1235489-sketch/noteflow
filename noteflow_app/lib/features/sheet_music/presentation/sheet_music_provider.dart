import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../data/midi_parser.dart';
import '../domain/sheet_data.dart';

/// 樂譜載入狀態
enum SheetLoadStatus { idle, loading, loaded, error }

class SheetMusicState {
  final SheetLoadStatus status;
  final SheetData? sheetData;
  final String? musicXml;  // MusicXML 內容（用於 OSMD 渲染）
  final String? errorMessage;
  final int? highlightedNoteIndex;
  final int? highlightedMeasure;

  const SheetMusicState({
    this.status = SheetLoadStatus.idle,
    this.sheetData,
    this.musicXml,
    this.errorMessage,
    this.highlightedNoteIndex,
    this.highlightedMeasure,
  });

  SheetMusicState copyWith({
    SheetLoadStatus? status,
    SheetData? sheetData,
    String? musicXml,
    String? errorMessage,
    int? highlightedNoteIndex,
    int? highlightedMeasure,
  }) {
    return SheetMusicState(
      status: status ?? this.status,
      sheetData: sheetData ?? this.sheetData,
      musicXml: musicXml ?? this.musicXml,
      errorMessage: errorMessage ?? this.errorMessage,
      highlightedNoteIndex: highlightedNoteIndex ?? this.highlightedNoteIndex,
      highlightedMeasure: highlightedMeasure ?? this.highlightedMeasure,
    );
  }
}

final sheetMusicProvider = StateNotifierProvider.family<
    SheetMusicNotifier, SheetMusicState, String>(
  (ref, transcriptionId) => SheetMusicNotifier(transcriptionId),
);

class SheetMusicNotifier extends StateNotifier<SheetMusicState> {
  final String transcriptionId;
  final MidiParser _parser = MidiParser();
  Timer? _pollingTimer;

  SheetMusicNotifier(this.transcriptionId) : super(const SheetMusicState());

  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> loadMidi() async {
    state = state.copyWith(status: SheetLoadStatus.loading);

    try {
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        receiveTimeout: const Duration(minutes: 10),
      ));

      final midiDio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 10),
      ));

      // 先檢查轉譜狀態
      final statusResponse = await dio.get<Map<String, dynamic>>(
        '/transcriptions/$transcriptionId',
      );

      final data = statusResponse.data?['data'];
      if (data == null) {
        // 轉錄不存在
        state = state.copyWith(
          status: SheetLoadStatus.error,
          errorMessage: '找不到轉譜記錄',
        );
        return;
      }

      final status = data['status'] ?? '';
      if (status != 'completed') {
        // 轉譜尚未完成，開始輪詢
        final progress = data['progress'] ?? 0;
        final progressMessage = data['progress_message'] ?? '處理中';
        state = state.copyWith(
          status: SheetLoadStatus.loading,
          errorMessage: '轉譜處理中 ($progress%)：$progressMessage',
        );
        _startPolling(dio, midiDio);
        return;
      }

      // Load MIDI and MusicXML in parallel for faster loading
      final midiFuture = midiDio.get<List<int>>(
        '/transcriptions/$transcriptionId/midi',
      );
      final xmlFuture = dio.get<String>(
        '/transcriptions/$transcriptionId/musicxml',
      ).catchError((_) => Response<String>(
        requestOptions: RequestOptions(),
        data: null,
      ));

      final results = await Future.wait([midiFuture, xmlFuture]);

      final midiResponse = results[0] as Response<List<int>>;
      final xmlResponse = results[1] as Response<String>;

      final midiBytes = Uint8List.fromList(midiResponse.data!);
      final result = _parser.parseWithMeta(midiBytes);

      final sheetData = SheetData.fromNotes(
        notes: result.notes,
        tempo: result.tempo,
        beatsPerMeasure: result.beatsPerMeasure,
        beatUnit: result.beatUnit,
      );

      state = state.copyWith(
        status: SheetLoadStatus.loaded,
        sheetData: sheetData,
        musicXml: xmlResponse.data,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 202) {
        // 轉譜處理中，開始輪詢
        state = state.copyWith(
          status: SheetLoadStatus.loading,
          errorMessage: '轉譜處理中，請稍候...',
        );
        _startPolling(
          Dio(BaseOptions(baseUrl: AppConstants.apiBaseUrl)),
          Dio(BaseOptions(baseUrl: AppConstants.apiBaseUrl, responseType: ResponseType.bytes)),
        );
      } else {
        state = state.copyWith(
          status: SheetLoadStatus.error,
          errorMessage: '載入樂譜失敗: ${error.message}',
        );
      }
    } on FormatException catch (error) {
      state = state.copyWith(
        status: SheetLoadStatus.error,
        errorMessage: 'MIDI 格式錯誤: ${error.message}',
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: SheetLoadStatus.error,
        errorMessage: '未知錯誤: $error',
      );
    }
  }

  void _startPolling(Dio dio, Dio midiDio) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollStatus(dio, midiDio),
    );
  }

  Future<void> _pollStatus(Dio dio, Dio midiDio) async {
    try {
      final statusResponse = await dio.get<Map<String, dynamic>>(
        '/transcriptions/$transcriptionId',
      );

      final data = statusResponse.data?['data'];
      if (data == null) {
        _pollingTimer?.cancel();
        state = state.copyWith(
          status: SheetLoadStatus.error,
          errorMessage: '找不到轉譜記錄',
        );
        return;
      }

      final status = data['status'] ?? '';
      final progress = data['progress'] ?? 0;
      final progressMessage = data['progress_message'] ?? '';

      if (status == 'completed') {
        // 轉譜完成，停止輪詢並載入 MIDI
        _pollingTimer?.cancel();
        await _loadMidiData(dio, midiDio);
      } else if (status == 'failed') {
        // 轉譜失敗
        _pollingTimer?.cancel();
        state = state.copyWith(
          status: SheetLoadStatus.error,
          errorMessage: '轉譜失敗：${data['error'] ?? '未知錯誤'}',
        );
      } else {
        // 仍在處理中，更新進度訊息
        state = state.copyWith(
          errorMessage: '轉譜處理中 ($progress%)：$progressMessage',
        );
      }
    } catch (e) {
      // 輪詢錯誤，繼續嘗試
      print('Polling error: $e');
    }
  }

  Future<void> _loadMidiData(Dio dio, Dio midiDio) async {
    try {
      // Load MIDI and MusicXML in parallel for faster loading
      final midiFuture = midiDio.get<List<int>>(
        '/transcriptions/$transcriptionId/midi',
      );
      final xmlFuture = dio.get<String>(
        '/transcriptions/$transcriptionId/musicxml',
      ).catchError((_) => Response<String>(
        requestOptions: RequestOptions(),
        data: null,
      ));

      final results = await Future.wait([midiFuture, xmlFuture]);

      final midiResponse = results[0] as Response<List<int>>;
      final xmlResponse = results[1] as Response<String>;

      final midiBytes = Uint8List.fromList(midiResponse.data!);
      final result = _parser.parseWithMeta(midiBytes);

      final sheetData = SheetData.fromNotes(
        notes: result.notes,
        tempo: result.tempo,
        beatsPerMeasure: result.beatsPerMeasure,
        beatUnit: result.beatUnit,
      );

      state = state.copyWith(
        status: SheetLoadStatus.loaded,
        sheetData: sheetData,
        musicXml: xmlResponse.data,
      );
    } catch (e) {
      state = state.copyWith(
        status: SheetLoadStatus.error,
        errorMessage: '載入 MIDI 失敗: $e',
      );
    }
  }

  void highlightNote(int noteIndex, int measure) {
    state = state.copyWith(
      highlightedNoteIndex: noteIndex,
      highlightedMeasure: measure,
    );
  }

  void clearHighlight() {
    state = const SheetMusicState().copyWith(
      status: state.status,
      sheetData: state.sheetData,
      musicXml: state.musicXml,
    );
  }
}
