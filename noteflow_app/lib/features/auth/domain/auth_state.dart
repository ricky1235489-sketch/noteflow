/// 認證狀態模型。
class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final String? userId;
  final String? email;
  final String? displayName;
  final bool isPro;
  final int monthlyConversionsUsed;
  final String? errorMessage;
  final String? idToken;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.userId,
    this.email,
    this.displayName,
    this.isPro = false,
    this.monthlyConversionsUsed = 0,
    this.errorMessage,
    this.idToken,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? userId,
    String? email,
    String? displayName,
    bool? isPro,
    int? monthlyConversionsUsed,
    String? errorMessage,
    String? idToken,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      isPro: isPro ?? this.isPro,
      monthlyConversionsUsed:
          monthlyConversionsUsed ?? this.monthlyConversionsUsed,
      errorMessage: errorMessage,
      idToken: idToken ?? this.idToken,
    );
  }

  static const initial = AuthState();
}
