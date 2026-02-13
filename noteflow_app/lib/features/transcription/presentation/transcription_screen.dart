import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/services/audio_recorder_service.dart';
import 'recording_provider.dart';
import 'transcription_provider.dart';

class TranscriptionScreen extends ConsumerWidget {
  const TranscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadState = ref.watch(uploadProvider);
    final notifier = ref.read(uploadProvider.notifier);

    // Navigate to sheet music when completed
    ref.listen(uploadProvider, (prev, next) {
      if (next.status == UploadStatus.completed && next.result != null) {
        final historyNotifier = ref.read(historyProvider.notifier);
        historyNotifier.addTranscription(next.result!);
        // Navigate to homepage instead of sheet music directly
        // This allows users to see all transcriptions and their status
        context.go('/');
        notifier.reset();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('新增轉譜')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _buildContent(context, ref, uploadState, notifier),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    UploadState state,
    UploadNotifier notifier,
  ) {
    switch (state.status) {
      case UploadStatus.idle:
      case UploadStatus.picking:
        return _IdleView(onUpload: notifier.pickAndUploadFile);
      case UploadStatus.uploading:
        return _UploadingView(
          fileName: state.fileName ?? '',
          progress: state.uploadProgress,
        );
      case UploadStatus.processing:
        return _ProcessingView(
          transcriptionId: state.result?.id ?? '',
        );
      case UploadStatus.failed:
        return _ErrorView(
          message: state.errorMessage ?? '未知錯誤',
          onRetry: notifier.reset,
        );
      case UploadStatus.completed:
        return const SizedBox.shrink();
    }
  }
}

class _IdleView extends ConsumerStatefulWidget {
  final VoidCallback onUpload;
  const _IdleView({required this.onUpload});

  @override
  ConsumerState<_IdleView> createState() => _IdleViewState();
}

class _IdleViewState extends ConsumerState<_IdleView> {
  String _selectedComposer = 'composer4'; // Default: Balanced

  final Map<String, String> _composerOptions = {
    'composer2': 'Simple & Clean (簡單清晰)',
    'composer4': 'Balanced (平衡推薦) ⭐',
    'composer7': 'Rich & Complex (豐富複雜)',
    'composer10': 'Moderate (中等難度)',
    'composer15': 'Full Arrangement (完整編曲)',
    'composer20': 'Advanced (進階)',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Composer selection card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.piano, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '編曲風格',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedComposer,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: _composerOptions.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedComposer = value);
                      // Store selection in provider
                      ref.read(uploadProvider.notifier).setComposer(value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '選擇 AI 編曲風格，影響樂譜的複雜度和音符密度',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _OptionCard(
          icon: Icons.upload_file,
          title: '上傳音樂檔案',
          subtitle: '支援 MP3、WAV、M4A',
          onTap: widget.onUpload,
        ),
        const SizedBox(height: 16),
        _OptionCard(
          icon: Icons.mic,
          title: '即時錄音',
          subtitle: '使用麥克風錄製音樂',
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _RecordingSheet(),
            );
          },
        ),
      ],
    );
  }
}

/// Bottom sheet for microphone recording
class _RecordingSheet extends ConsumerStatefulWidget {
  const _RecordingSheet();

  @override
  ConsumerState<_RecordingSheet> createState() => _RecordingSheetState();
}

class _RecordingSheetState extends ConsumerState<_RecordingSheet> {
  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Text('麥克風錄音', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              recordingState.isRecording
                  ? '錄音中...'
                  : recordingState.hasRecording
                      ? '錄音完成'
                      : '點擊開始錄音',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),

            // Timer display
            Text(
              _formatDuration(recordingState.elapsed),
              style: theme.textTheme.displaySmall?.copyWith(
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 32),

            // Recording indicator
            if (recordingState.isRecording)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.2),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),

            const SizedBox(height: 24),

            // Error message
            if (recordingState.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  recordingState.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!recordingState.isRecording && !recordingState.hasRecording)
                  FilledButton.icon(
                    onPressed: () {
                      ref.read(recordingStateProvider.notifier).startRecording();
                    },
                    icon: const Icon(Icons.mic),
                    label: const Text('開始錄音'),
                  ),

                if (recordingState.isRecording) ...[
                  FilledButton.icon(
                    onPressed: () {
                      final uploadNotifier = ref.read(uploadProvider.notifier);
                      ref
                          .read(recordingStateProvider.notifier)
                          .stopAndUpload(uploadNotifier);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('停止並轉譜'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () {
                      ref.read(recordingStateProvider.notifier).cancel();
                      Navigator.pop(context);
                    },
                    child: const Text('取消'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _UploadingView extends StatelessWidget {
  final String fileName;
  final double progress;
  const _UploadingView({required this.fileName, required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('上傳中...', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(fileName, style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text('${(progress * 100).toInt()}%', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProcessingView extends ConsumerStatefulWidget {
  final String transcriptionId;
  const _ProcessingView({required this.transcriptionId});

  @override
  ConsumerState<_ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends ConsumerState<_ProcessingView> {
  Timer? _pollingTimer;
  int _progress = 0;
  String _progressMessage = '準備中...';

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final dio = Dio(BaseOptions(baseUrl: AppConstants.apiBaseUrl));
        final response = await dio.get<Map<String, dynamic>>(
          '/transcriptions/${widget.transcriptionId}',
        );
        final data = response.data?['data'] as Map<String, dynamic>?;
        if (data != null) {
          final status = data['status'] as String? ?? '';
          final progress = (data['progress'] as num?)?.toInt() ?? 0;
          final progressMessage = (data['progress_message'] as String?) ?? '';

          setState(() {
            _progress = progress;
            _progressMessage = progressMessage;
          });

          // 如果完成，導航到首頁
          if (status == 'completed') {
            if (mounted) {
              _pollingTimer?.cancel();
              context.go('/');
            }
          }
        }
      } on Exception catch (e) {
        // 靜默失敗，繼續輪詢
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  children: [
                    Center(
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          value: _progress / 100,
                          strokeWidth: 6,
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '$_progress%',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'AI 正在分析音樂...',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _progressMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '辨識音高、節奏，產生鋼琴樂譜',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 24),
              // 提示用戶可以返回首頁
              OutlinedButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home),
                label: const Text('前往首頁'),
              ),
              const SizedBox(height: 8),
              Text(
                '轉譜完成後會自動更新',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('轉譜失敗', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重試'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 40, color: theme.colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
