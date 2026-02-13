import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'export_service.dart';

/// 匯出狀態
enum ExportStatus { idle, exporting, success, error }

class ExportState {
  final ExportStatus status;
  final String? errorMessage;

  const ExportState({
    this.status = ExportStatus.idle,
    this.errorMessage,
  });

  ExportState copyWith({
    ExportStatus? status,
    String? errorMessage,
  }) {
    return ExportState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final exportProvider =
    StateNotifierProvider<ExportNotifier, ExportState>((ref) {
  return ExportNotifier();
});

class ExportNotifier extends StateNotifier<ExportState> {
  final ExportService _service = ExportService();

  ExportNotifier() : super(const ExportState());

  Future<void> exportMidi({
    required String transcriptionId,
    required String title,
  }) async {
    state = state.copyWith(status: ExportStatus.exporting);
    try {
      await _service.exportMidi(
        transcriptionId: transcriptionId,
        title: title,
      );
      state = state.copyWith(status: ExportStatus.success);
      // 自動重置狀態
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        state = state.copyWith(status: ExportStatus.idle);
      }
    } on Exception catch (error) {
      state = state.copyWith(
        status: ExportStatus.error,
        errorMessage: '匯出 MIDI 失敗: $error',
      );
    }
  }

  Future<void> exportPdf({
    required String transcriptionId,
    required String title,
  }) async {
    state = state.copyWith(status: ExportStatus.exporting);
    try {
      await _service.exportPdf(
        transcriptionId: transcriptionId,
        title: title,
      );
      state = state.copyWith(status: ExportStatus.success);
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        state = state.copyWith(status: ExportStatus.idle);
      }
    } on Exception catch (error) {
      state = state.copyWith(
        status: ExportStatus.error,
        errorMessage: '匯出 PDF 失敗: $error',
      );
    }
  }
}
