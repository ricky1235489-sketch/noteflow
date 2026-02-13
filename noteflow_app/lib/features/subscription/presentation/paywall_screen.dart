import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'subscription_provider.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(subscriptionProvider.notifier).loadOfferings(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subState = ref.watch(subscriptionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('升級 Pro')),
      body: subState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero section
                  Icon(
                    Icons.star_rounded,
                    size: 64,
                    color: Colors.amber.shade600,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'NoteFlow Pro',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '解鎖無限轉譜，享受完整功能',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Feature comparison
                  _FeatureComparisonCard(),
                  const SizedBox(height: 24),

                  // Web notice
                  if (kIsWeb) ...[
                    Card(
                      color: theme.colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: theme.colorScheme.onTertiaryContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '訂閱功能請在 iOS 或 Android App 中操作',
                                style: TextStyle(
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Subscription packages
                  if (!kIsWeb) ...[
                    if (subState.availablePackages.isEmpty &&
                        !subState.isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          '目前無可用的訂閱方案',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),

                    ...subState.availablePackages.map(
                      (pkg) => _PackageCard(
                        package: pkg,
                        onPurchase: () => _handlePurchase(pkg),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Restore purchases
                    TextButton(
                      onPressed: () {
                        ref
                            .read(subscriptionProvider.notifier)
                            .restorePurchases();
                      },
                      child: const Text('恢復先前購買'),
                    ),
                  ],

                  // Error message
                  if (subState.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        subState.errorMessage!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  // Already pro
                  if (subState.isProActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Card(
                        color: Colors.green.shade50,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text(
                                '你已是 Pro 會員',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _handlePurchase(Package package) async {
    final success =
        await ref.read(subscriptionProvider.notifier).purchase(package);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('升級成功！歡迎使用 Pro 功能')),
      );
      Navigator.pop(context);
    }
  }
}

class _FeatureComparisonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _FeatureRow(
              feature: '每月轉譜次數',
              free: '3 次',
              pro: '無限',
            ),
            const Divider(height: 24),
            _FeatureRow(
              feature: '音訊長度上限',
              free: '30 秒',
              pro: '10 分鐘',
            ),
            const Divider(height: 24),
            _FeatureRow(
              feature: 'PDF / MIDI 匯出',
              free: '✓',
              pro: '✓',
            ),
            const Divider(height: 24),
            _FeatureRow(
              feature: '優先處理',
              free: '—',
              pro: '✓',
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String feature;
  final String free;
  final String pro;

  const _FeatureRow({
    required this.feature,
    required this.free,
    required this.pro,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(feature, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          flex: 2,
          child: Text(
            free,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            pro,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.amber.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Package package;
  final VoidCallback onPurchase;

  const _PackageCard({
    required this.package,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = package.storeProduct;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onPurchase,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (product.description.isNotEmpty)
                      Text(
                        product.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onPurchase,
                child: Text(product.priceString),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
