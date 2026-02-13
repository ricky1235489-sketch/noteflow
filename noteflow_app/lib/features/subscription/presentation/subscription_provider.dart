import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../core/constants/app_constants.dart';
import '../../auth/presentation/auth_provider.dart';
import '../../transcription/presentation/transcription_provider.dart';

/// Subscription state
class SubscriptionState {
  final bool isProActive;
  final bool isLoading;
  final String? errorMessage;
  final List<Package> availablePackages;
  final String? activeSubscriptionId;

  const SubscriptionState({
    this.isProActive = false,
    this.isLoading = false,
    this.errorMessage,
    this.availablePackages = const [],
    this.activeSubscriptionId,
  });

  SubscriptionState copyWith({
    bool? isProActive,
    bool? isLoading,
    String? errorMessage,
    List<Package>? availablePackages,
    String? activeSubscriptionId,
  }) {
    return SubscriptionState(
      isProActive: isProActive ?? this.isProActive,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      availablePackages: availablePackages ?? this.availablePackages,
      activeSubscriptionId: activeSubscriptionId ?? this.activeSubscriptionId,
    );
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final authState = ref.watch(authProvider);
  return SubscriptionNotifier(
    apiClient: apiClient,
    userId: authState.userId,
  );
});

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final dynamic _apiClient;
  final String? _userId;
  bool _initialized = false;

  SubscriptionNotifier({
    required dynamic apiClient,
    required String? userId,
  })  : _apiClient = apiClient,
        _userId = userId,
        super(const SubscriptionState());

  /// Initialize RevenueCat SDK
  Future<void> initialize() async {
    if (_initialized || kIsWeb) return; // RevenueCat doesn't support web

    try {
      state = state.copyWith(isLoading: true);

      await Purchases.configure(
        PurchasesConfiguration(AppConstants.revenueCatApiKey)
          ..appUserID = _userId,
      );

      _initialized = true;
      await _refreshStatus();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '訂閱服務初始化失敗: $e',
      );
    }
  }

  /// Refresh subscription status from RevenueCat
  Future<void> _refreshStatus() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final isActive = customerInfo.entitlements.active.containsKey('pro');

      state = state.copyWith(
        isProActive: isActive,
        isLoading: false,
        activeSubscriptionId: isActive
            ? customerInfo.entitlements.active['pro']?.productIdentifier
            : null,
      );

      // Sync to backend
      await _syncToBackend(isActive);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Load available subscription packages
  Future<void> loadOfferings() async {
    if (kIsWeb) return;

    try {
      state = state.copyWith(isLoading: true);

      if (!_initialized) await initialize();

      final offerings = await Purchases.getOfferings();
      final current = offerings.current;

      if (current != null) {
        state = state.copyWith(
          availablePackages: current.availablePackages,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '無法載入訂閱方案: $e',
      );
    }
  }

  /// Purchase a subscription package
  Future<bool> purchase(Package package) async {
    try {
      state = state.copyWith(isLoading: true, errorMessage: null);

      final result = await Purchases.purchasePackage(package);
      final isActive = result.entitlements.active.containsKey('pro');

      state = state.copyWith(
        isProActive: isActive,
        isLoading: false,
      );

      await _syncToBackend(isActive);
      return isActive;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        state = state.copyWith(isLoading: false);
        return false;
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: '購買失敗: $e',
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '購買失敗: $e',
      );
      return false;
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    try {
      state = state.copyWith(isLoading: true);

      final customerInfo = await Purchases.restorePurchases();
      final isActive = customerInfo.entitlements.active.containsKey('pro');

      state = state.copyWith(
        isProActive: isActive,
        isLoading: false,
      );

      await _syncToBackend(isActive);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '恢復購買失敗: $e',
      );
    }
  }

  /// Sync subscription status to backend
  Future<void> _syncToBackend(bool isPro) async {
    try {
      await _apiClient.post('/users/me/subscription', data: {
        'is_pro': isPro,
        'revenucat_user_id': _userId,
      });
    } catch (_) {
      // Silently fail — backend sync is best-effort
    }
  }
}
