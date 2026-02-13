import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../constants/app_constants.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient({String? baseUrl, String? authToken}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? AppConstants.apiBaseUrl,
        connectTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 10),
        headers: {
          'Content-Type': 'application/json',
          if (authToken != null) 'Authorization': 'Bearer $authToken',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
  }) async {
    return _dio.post<T>(path, data: data);
  }

  Future<Response<T>> delete<T>(String path) async {
    return _dio.delete<T>(path);
  }

  /// 上傳音訊檔案，回傳 file_key
  Future<Map<String, dynamic>> uploadAudio({
    required Uint8List fileBytes,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        fileBytes,
        filename: fileName,
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/upload/audio',
      data: formData,
      onSendProgress: onProgress,
    );

    return response.data!;
  }

  /// 建立轉譜任務
  Future<Map<String, dynamic>> createTranscription({
    required String title,
    required String audioFileKey,
    String? composer, // Optional composer style
  }) async {
    final data = {
      'title': title,
      'audio_file_key': audioFileKey,
    };
    
    if (composer != null) {
      data['composer'] = composer;
    }
    
    final response = await _dio.post<Map<String, dynamic>>(
      '/transcriptions',
      data: data,
    );

    return response.data!;
  }

  /// 取得轉譜歷史
  Future<Map<String, dynamic>> getTranscriptions() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/transcriptions',
    );

    return response.data!;
  }

  /// 取得單一轉譜結果
  Future<Map<String, dynamic>> getTranscription(String id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/transcriptions/$id',
    );

    return response.data!;
  }

  /// 刪除轉譜記錄
  Future<void> deleteTranscription(String id) async {
    await _dio.delete('/transcriptions/$id');
  }

  /// 刪除所有轉譜記錄
  Future<Map<String, dynamic>> deleteAllTranscriptions() async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/transcriptions/',
    );
    return response.data!;
  }

  /// 刪除選定的轉譜記錄
  Future<Map<String, dynamic>> deleteSelectedTranscriptions(
    List<String> ids,
  ) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/transcriptions/selected',
      data: ids,
    );
    return response.data!;
  }

  /// 下載檔案為 bytes
  Future<Uint8List> downloadBytes(String path) async {
    final response = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  void updateAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// 取得使用量統計
  Future<Map<String, dynamic>> getUsage() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/me/usage',
    );
    return response.data!;
  }

  /// 同步訂閱狀態至後端
  Future<Map<String, dynamic>> syncSubscription({
    required bool isPro,
    String? revenuecatUserId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/users/me/subscription',
      data: {
        'is_pro': isPro,
        'revenucat_user_id': revenuecatUserId,
      },
    );
    return response.data!;
  }
}
