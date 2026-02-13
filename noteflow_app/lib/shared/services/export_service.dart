import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:web/web.dart' as web;

import '../../core/constants/app_constants.dart';

/// 匯出服務 — 從後端下載 PDF/MIDI 並觸發瀏覽器下載
class ExportService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConstants.apiBaseUrl,
    responseType: ResponseType.bytes,
    receiveTimeout: const Duration(minutes: 10),
  ));

  /// 下載 MIDI 檔案
  Future<void> exportMidi({
    required String transcriptionId,
    required String title,
  }) async {
    final bytes = await _downloadFile(
      '/transcriptions/$transcriptionId/midi',
    );
    _triggerBrowserDownload(
      bytes: bytes,
      fileName: '$title.mid',
      mimeType: 'audio/midi',
    );
  }

  /// 下載 PDF 檔案
  Future<void> exportPdf({
    required String transcriptionId,
    required String title,
  }) async {
    final bytes = await _downloadFile(
      '/transcriptions/$transcriptionId/pdf',
    );
    _triggerBrowserDownload(
      bytes: bytes,
      fileName: '$title.pdf',
      mimeType: 'application/pdf',
    );
  }

  Future<Uint8List> _downloadFile(String path) async {
    final response = await _dio.get<List<int>>(path);
    return Uint8List.fromList(response.data!);
  }

  /// 使用 Web API 觸發瀏覽器下載
  void _triggerBrowserDownload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) {
    final base64Data = base64Encode(bytes);
    final dataUrl = 'data:$mimeType;base64,$base64Data';

    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = dataUrl;
    anchor.download = fileName;
    anchor.style.display = 'none';

    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }
}
