import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_provider.dart';
import '../domain/transcription_entity.dart';

// Shared API client provider — 自動注入 auth token
final apiClientProvider = Provider<ApiClient>((ref) {
  final authState = ref.watch(authProvider);
  return ApiClient(authToken: authState.idToken);
});

// Upload state
enum UploadStatus { idle, picking, uploading, processing, completed, failed }

class UploadState {
  final UploadStatus status;
  final String? fileName;
  final double uploadProgress;
  final String? errorMessage;
  final TranscriptionEntity? result;
  final String composer; // Selected composer style

  const UploadState({
    this.status = UploadStatus.idle,
    this.fileName,
    this.uploadProgress = 0.0,
    this.errorMessage,
    this.result,
    this.composer = 'composer4', // Default: Balanced
  });

  UploadState copyWith({
    UploadStatus? status,
    String? fileName,
    double? uploadProgress,
    String? errorMessage,
    TranscriptionEntity? result,
    String? composer,
  }) {
    return UploadState(
      status: status ?? this.status,
      fileName: fileName ?? this.fileName,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
      result: result ?? this.result,
      composer: composer ?? this.composer,
    );
  }
}

// History state
class TranscriptionHistoryState {
  final List<TranscriptionEntity> items;
  final bool isLoading;

  const TranscriptionHistoryState({
    this.items = const [],
    this.isLoading = false,
  });

  TranscriptionHistoryState copyWith({
    List<TranscriptionEntity>? items,
    bool? isLoading,
  }) {
    return TranscriptionHistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Upload notifier
final uploadProvider =
    StateNotifierProvider<UploadNotifier, UploadState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UploadNotifier(apiClient: apiClient);
});

class UploadNotifier extends StateNotifier<UploadState> {
  final ApiClient _apiClient;

  UploadNotifier({required ApiClient apiClient})
      : _apiClient = apiClient,
        super(const UploadState());

  /// Set the selected composer style
  void setComposer(String composer) {
    state = state.copyWith(composer: composer);
  }

  Future<void> pickAndUploadFile() async {
    state = state.copyWith(status: UploadStatus.picking);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'm4a'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        state = const UploadState();
        return;
      }

      final file = result.files.first;
      final fileBytes = file.bytes;

      if (fileBytes == null) {
        state = state.copyWith(
          status: UploadStatus.failed,
          errorMessage: '無法讀取檔案內容',
        );
        return;
      }

      final fileName = file.name;

      // Step 1: Upload audio file
      state = state.copyWith(
        status: UploadStatus.uploading,
        fileName: fileName,
        uploadProgress: 0.0,
      );

      final uploadResponse = await _apiClient.uploadAudio(
        fileBytes: fileBytes,
        fileName: fileName,
        onProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(uploadProgress: sent / total);
          }
        },
      );

      final fileKey = uploadResponse['data']?['file_key'] as String?;
      if (fileKey == null) {
        state = state.copyWith(
          status: UploadStatus.failed,
          errorMessage: '上傳回應格式錯誤',
        );
        return;
      }

      // Step 2: Create transcription
      state = state.copyWith(status: UploadStatus.processing);

      final title = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final transcriptionResponse = await _apiClient.createTranscription(
        title: title,
        audioFileKey: fileKey,
        composer: state.composer, // Pass selected composer
      );

      final data = transcriptionResponse['data'] as Map<String, dynamic>?;
      if (data == null) {
        state = state.copyWith(
          status: UploadStatus.failed,
          errorMessage: '轉譜回應格式錯誤',
        );
        return;
      }

      final entity = TranscriptionEntity(
        id: data['id'] as String,
        title: data['title'] as String,
        status: _parseStatus(data['status'] as String),
        createdAt: DateTime.parse(data['created_at'] as String),
        completedAt: data['completed_at'] != null
            ? DateTime.parse(data['completed_at'] as String)
            : null,
        durationSeconds: (data['duration_seconds'] as num?)?.toDouble(),
      );

      state = state.copyWith(
        status: UploadStatus.completed,
        result: entity,
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: UploadStatus.failed,
        errorMessage: '上傳失敗: $error',
      );
    }
  }

  /// Upload pre-recorded audio bytes (from microphone recording).
  Future<void> uploadRecordedAudio({
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    state = state.copyWith(
      status: UploadStatus.uploading,
      fileName: fileName,
      uploadProgress: 0.0,
    );

    try {
      final uploadResponse = await _apiClient.uploadAudio(
        fileBytes: fileBytes,
        fileName: fileName,
        onProgress: (sent, total) {
          if (total > 0) {
            state = state.copyWith(uploadProgress: sent / total);
          }
        },
      );

      final fileKey = uploadResponse['data']?['file_key'] as String?;
      if (fileKey == null) {
        state = state.copyWith(
          status: UploadStatus.failed,
          errorMessage: '上傳回應格式錯誤',
        );
        return;
      }

      state = state.copyWith(status: UploadStatus.processing);

      final title = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final transcriptionResponse = await _apiClient.createTranscription(
        title: title,
        audioFileKey: fileKey,
        composer: state.composer, // Pass selected composer
      );

      final data = transcriptionResponse['data'] as Map<String, dynamic>?;
      if (data == null) {
        state = state.copyWith(
          status: UploadStatus.failed,
          errorMessage: '轉譜回應格式錯誤',
        );
        return;
      }

      final entity = TranscriptionEntity(
        id: data['id'] as String,
        title: data['title'] as String,
        status: _parseStatus(data['status'] as String),
        createdAt: DateTime.parse(data['created_at'] as String),
        completedAt: data['completed_at'] != null
            ? DateTime.parse(data['completed_at'] as String)
            : null,
        durationSeconds: (data['duration_seconds'] as num?)?.toDouble(),
      );

      state = state.copyWith(
        status: UploadStatus.completed,
        result: entity,
      );
    } on Exception catch (error) {
      state = state.copyWith(
        status: UploadStatus.failed,
        errorMessage: '上傳失敗: $error',
      );
    }
  }

  void reset() {
    state = const UploadState();
  }

  TranscriptionStatus _parseStatus(String status) {
    switch (status) {
      case 'completed':
        return TranscriptionStatus.completed;
      case 'processing':
        return TranscriptionStatus.processing;
      case 'failed':
        return TranscriptionStatus.failed;
      default:
        return TranscriptionStatus.pending;
    }
  }
}

// History notifier
final historyProvider =
    StateNotifierProvider<HistoryNotifier, TranscriptionHistoryState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return HistoryNotifier(apiClient: apiClient);
});

class HistoryNotifier extends StateNotifier<TranscriptionHistoryState> {
  final ApiClient _apiClient;
  Timer? _refreshTimer;

  HistoryNotifier({required ApiClient apiClient})
      : _apiClient = apiClient,
        super(const TranscriptionHistoryState()) {
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    // 每 3 秒自動刷新一次（如果有正在處理的項目）
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkProcessingItems();
    });
  }

  Future<void> _checkProcessingItems() async {
    // 只有當有待處理的項目時才刷新
    final hasProcessing = state.items.any((item) => item.isProcessing);
    if (hasProcessing) {
      await loadHistory();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadHistory() async {
    state = state.copyWith(isLoading: true);

    try {
      final response = await _apiClient.getTranscriptions();
      final dataList = response['data'] as List<dynamic>? ?? [];

      final items = dataList.map((item) {
        final map = item as Map<String, dynamic>;
        return TranscriptionEntity(
          id: map['id'] as String,
          title: map['title'] as String,
          status: _parseStatus(map['status'] as String),
          createdAt: DateTime.parse(map['created_at'] as String),
          completedAt: map['completed_at'] != null
              ? DateTime.parse(map['completed_at'] as String)
              : null,
          durationSeconds: (map['duration_seconds'] as num?)?.toDouble(),
          progress: (map['progress'] as num?)?.toInt() ?? 0,
          progressMessage: (map['progress_message'] as String?) ?? "Waiting",
          midiUrl: map['midi_url'] as String?,
          pdfUrl: map['pdf_url'] as String?,
          musicXmlUrl: map['musicxml_url'] as String?,
        );
      }).toList();

      state = state.copyWith(items: items, isLoading: false);
    } on Exception {
      state = state.copyWith(isLoading: false);
    }
  }

  void addTranscription(TranscriptionEntity item) {
    state = state.copyWith(items: [item, ...state.items]);
  }

  Future<void> removeTranscription(String id) async {
    try {
      await _apiClient.deleteTranscription(id);
      state = state.copyWith(
        items: state.items.where((item) => item.id != id).toList(),
      );
    } on Exception {
      // silently fail for now
    }
  }

  Future<void> deleteAllTranscriptions() async {
    try {
      await _apiClient.deleteAllTranscriptions();
      state = state.copyWith(items: []);
    } on Exception {
      // silently fail for now
    }
  }

  Future<void> deleteSelectedTranscriptions(List<String> ids) async {
    try {
      await _apiClient.deleteSelectedTranscriptions(ids);
      state = state.copyWith(
        items: state.items.where((item) => !ids.contains(item.id)).toList(),
      );
    } on Exception {
      // silently fail for now
    }
  }

  TranscriptionStatus _parseStatus(String status) {
    switch (status) {
      case 'completed':
        return TranscriptionStatus.completed;
      case 'processing':
        return TranscriptionStatus.processing;
      case 'failed':
        return TranscriptionStatus.failed;
      default:
        return TranscriptionStatus.pending;
    }
  }
}
