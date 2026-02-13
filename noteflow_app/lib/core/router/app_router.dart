import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/subscription/presentation/paywall_screen.dart';
import '../../features/transcription/presentation/transcription_screen.dart';
import '../../features/transcription/presentation/sheet_music_screen.dart';

/// 訪客模式 — 允許未登入使用基本功能
final guestModeProvider = StateProvider<bool>((ref) => true);

/// 全域 GoRouter 實例（不隨 auth 狀態重建）
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/transcribe',
      builder: (context, state) => const TranscriptionScreen(),
    ),
    GoRoute(
      path: '/sheet/:id',
      builder: (context, state) {
        final transcriptionId = state.pathParameters['id'] ?? '';
        return SheetMusicScreen(transcriptionId: transcriptionId);
      },
    ),
    GoRoute(
      path: '/paywall',
      builder: (context, state) => const PaywallScreen(),
    ),
  ],
);
