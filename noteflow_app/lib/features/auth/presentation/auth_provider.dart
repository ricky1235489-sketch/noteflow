import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/constants/app_constants.dart';
import '../domain/auth_state.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.initial) {
    _listenAuthChanges();
  }

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authSubscription;

  void _listenAuthChanges() {
    try {
      _authSubscription = _firebaseAuth.authStateChanges().listen(
        (user) async {
          if (user != null) {
            await _syncWithBackend(user);
          } else {
            state = AuthState.initial;
          }
        },
        onError: (e) {
          debugPrint('Auth stream error: $e');
        },
      );
    } catch (e) {
      debugPrint('Firebase Auth not available: $e');
    }
  }

  Future<void> _syncWithBackend(User firebaseUser) async {
    try {
      final idToken = await firebaseUser.getIdToken();
      if (idToken == null) return;

      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
      ));

      final response = await dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'firebase_token': idToken},
      );

      final userData = response.data?['data'] as Map<String, dynamic>?;

      state = AuthState(
        isAuthenticated: true,
        userId: userData?['id']?.toString(),
        email: firebaseUser.email,
        displayName: userData?['display_name'] as String? ??
            firebaseUser.displayName,
        isPro: userData?['is_pro'] as bool? ?? false,
        monthlyConversionsUsed:
            userData?['monthly_conversions_used'] as int? ?? 0,
        idToken: idToken,
      );
    } on DioException {
      // 後端不可用時仍允許使用（離線模式）
      final idToken = await firebaseUser.getIdToken();
      state = AuthState(
        isAuthenticated: true,
        userId: firebaseUser.uid,
        email: firebaseUser.email,
        displayName: firebaseUser.displayName,
        idToken: idToken,
      );
    }
  }


  /// Email + 密碼註冊
  Future<void> registerWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final credential =
          await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (displayName != null && credential.user != null) {
        await credential.user!.updateDisplayName(displayName);
      }
      // authStateChanges listener 會自動觸發 _syncWithBackend
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _mapFirebaseError(e.code),
      );
    }
  }

  /// Email + 密碼登入
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _mapFirebaseError(e.code),
      );
    }
  }

  /// 登出
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    state = AuthState.initial;
  }

  /// 重新取得 ID Token（給 API Client 用）
  Future<String?> getIdToken() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// 清除錯誤訊息
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return '此 Email 已被註冊';
      case 'invalid-email':
        return 'Email 格式不正確';
      case 'weak-password':
        return '密碼強度不足（至少 6 個字元）';
      case 'user-not-found':
        return '找不到此帳號';
      case 'wrong-password':
        return '密碼錯誤';
      case 'invalid-credential':
        return 'Email 或密碼錯誤';
      case 'too-many-requests':
        return '登入嘗試次數過多，請稍後再試';
      case 'user-disabled':
        return '此帳號已被停用';
      default:
        return '登入失敗：$code';
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
