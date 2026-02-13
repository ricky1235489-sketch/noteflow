import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/presentation/auth_provider.dart';

class NoteFlowApp extends ConsumerStatefulWidget {
  const NoteFlowApp({super.key});

  @override
  ConsumerState<NoteFlowApp> createState() => _NoteFlowAppState();
}

class _NoteFlowAppState extends ConsumerState<NoteFlowApp> {
  @override
  Widget build(BuildContext context) {
    // 監聽 auth 狀態變化，自動導向
    ref.listen(authProvider, (prev, next) {
      final isGuest = ref.read(guestModeProvider);
      if (next.isAuthenticated || isGuest) {
        appRouter.go('/');
      } else if (prev?.isAuthenticated == true && !next.isAuthenticated) {
        appRouter.go('/login');
      }
    });

    ref.listen(guestModeProvider, (prev, next) {
      if (next) {
        appRouter.go('/');
      } else if (prev == true && !next) {
        appRouter.go('/login');
      }
    });

    return MaterialApp.router(
      title: 'NoteFlow',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
