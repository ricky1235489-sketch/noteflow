import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/export_provider.dart';
import '../../playback/domain/playback_state.dart';
import '../../playback/presentation/playback_controls.dart';
import '../../playback/presentation/playback_provider.dart';
import '../../sheet_music/domain/sheet_data.dart';
import '../../sheet_music/presentation/sheet_music_provider.dart';
import '../../sheet_music/presentation/sheet_music_widget.dart';
import '../../sheet_music/presentation/staff_painter.dart';
import '../../sheet_music/presentation/osmd_sheet_stub.dart'
    if (dart.library.js_interop) '../../sheet_music/presentation/osmd_sheet_widget.dart';

class SheetMusicScreen extends ConsumerStatefulWidget {
  final String transcriptionId;

  const SheetMusicScreen({
    super.key,
    required this.transcriptionId,
  });

  @override
  ConsumerState<SheetMusicScreen> createState() => _SheetMusicScreenState();
}

class _SheetMusicScreenState extends ConsumerState<SheetMusicScreen> with WidgetsBindingObserver {
  final TransformationController _transformController =
      TransformationController();
  int _lastScrolledLine = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref
          .read(sheetMusicProvider(widget.transcriptionId).notifier)
          .loadMidi();
    });
  }

  @override
  void deactivate() {
    // Stop playback when navigating away (called before dispose)
    // Don't call stop() as it modifies provider state during widget lifecycle
    // The provider will auto-dispose and clean up properly
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheetState = ref.watch(sheetMusicProvider(widget.transcriptionId));
    final playbackState = ref.watch(playbackProvider);
    final exportState = ref.watch(exportProvider);
    final theme = Theme.of(context);

    // 樂譜載入完成後，自動載入到播放器
    ref.listen(
      sheetMusicProvider(widget.transcriptionId),
      (previous, next) {
        if (next.status == SheetLoadStatus.loaded &&
            next.sheetData != null &&
            (previous?.status != SheetLoadStatus.loaded)) {
          ref.read(playbackProvider.notifier).loadSheetData(next.sheetData!);
        }
      },
    );

    // 播放時自動捲動到當前小節所在的 system line
    ref.listen(playbackProvider, (previous, next) {
      if (next.isPlaying && sheetState.sheetData != null) {
        _autoScrollToMeasure(next.currentMeasure);
      }
      if (next.isStopped && previous?.isPlaying == true) {
        _lastScrolledLine = -1;
      }
    });

    // 匯出狀態提示
    ref.listen(exportProvider, (previous, next) {
      if (next.status == ExportStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('匯出成功'),
            duration: Duration(seconds: 2),
          ),
        );
      } else if (next.status == ExportStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? '匯出失敗'),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    });

    final isExporting = exportState.status == ExportStatus.exporting;
    final isLoaded = sheetState.status == SheetLoadStatus.loaded;

    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop) {
          // Stop playback when navigating back
          ref.read(playbackProvider.notifier).stop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('樂譜'),
          actions: [
          IconButton(
            icon: isExporting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
            tooltip: '匯出 PDF',
            onPressed: isLoaded && !isExporting
                ? () => _exportPdf(context) : null,
          ),
          IconButton(
            icon: const Icon(Icons.piano),
            tooltip: '匯出 MIDI',
            onPressed: isLoaded && !isExporting
                ? () => _exportMidi(context) : null,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '分享',
            onPressed: isLoaded ? () => _share(context) : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: theme.colorScheme.surface,
              child: _buildSheetContent(sheetState, playbackState, theme),
            ),
          ),
          const PlaybackControls(),
        ],
      ),
      ),
    );
  }

  /// 自動捲動到指定小節所在的 system line
  void _autoScrollToMeasure(int measureIndex) {
    final currentLine = measureIndex ~/ StaffConstants.measuresPerLine;
    if (currentLine == _lastScrolledLine) return;
    _lastScrolledLine = currentLine;

    final targetY = StaffConstants.systemYForMeasure(measureIndex);
    // 捲動到讓目標 system line 在畫面上方留一點 margin
    final scrollY = (targetY - 20).clamp(0.0, double.infinity);

    final currentMatrix = _transformController.value.clone();
    // 保留目前的縮放，只改 Y 平移
    final scale = currentMatrix.getMaxScaleOnAxis();
    final currentTranslateX = currentMatrix.getTranslation().x;

    final newMatrix = Matrix4.identity()
      ..scale(scale)
      ..setTranslationRaw(currentTranslateX, -scrollY * scale, 0);

    _transformController.value = newMatrix;
  }

  /// 計算播放游標在當前小節內的進度
  double? _calcCursorProgress(PlaybackState playbackState, SheetData? sheetData) {
    if (!playbackState.isPlaying || sheetData == null) return null;
    final measureIndex = playbackState.currentMeasure;
    if (measureIndex < 0 || measureIndex >= sheetData.measures.length) {
      return null;
    }

    final measure = sheetData.measures[measureIndex];
    final measureDuration = measure.endTime - measure.startTime;
    if (measureDuration <= 0) return 0.0;

    final currentSec =
        playbackState.currentPosition.inMilliseconds / 1000.0;
    final progress =
        (currentSec - measure.startTime) / measureDuration;
    return progress.clamp(0.0, 1.0);
  }

  Widget _buildSheetContent(
    SheetMusicState sheetState,
    PlaybackState playbackState,
    ThemeData theme,
  ) {
    switch (sheetState.status) {
      case SheetLoadStatus.idle:
      case SheetLoadStatus.loading:
        // 檢查是否為轉譜處理中
        final isProcessing = sheetState.errorMessage?.contains('處理中') ?? false;
        
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isProcessing)
                  Icon(Icons.music_note_outlined, size: 64, 
                      color: theme.colorScheme.primary)
                else
                  const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  isProcessing ? '轉譜處理中' : '載入樂譜中...',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  sheetState.errorMessage ?? '請稍候...',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                // 處理中顯示返回首頁按鈕
                if (isProcessing) ...[
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.home),
                    label: const Text('返回首頁'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '轉譜完成後可在此頁面查看',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  const Text('正在解析 MIDI 檔案...'),
                ],
              ],
            ),
          ),
        );

      case SheetLoadStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48,
                    color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  sheetState.errorMessage ?? '載入失敗',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(sheetMusicProvider(widget.transcriptionId)
                            .notifier)
                        .loadMidi();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
              ],
            ),
          ),
        );

      case SheetLoadStatus.loaded:
        final sheetData = sheetState.sheetData;
        final musicXml = sheetState.musicXml;
        
        if (sheetData == null || sheetData.measures.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.music_off, size: 48,
                    color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 16),
                Text(
                  '沒有偵測到音符',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }

        // 優先使用 OSMD 渲染（Web 平台且有 MusicXML）
        if (kIsWeb && musicXml != null && musicXml.isNotEmpty) {
          // Pass current measure, or -1 if stopped to hide cursor
          final currentMeasure = playbackState.isPlaying
              ? playbackState.currentMeasure
              : -1;
          
          return OsmdSheetWidget(
            musicXml: musicXml,
            currentMeasure: currentMeasure,
          );
        }

        // Fallback 到自訂 Canvas 渲染
        final highlightNote = playbackState.isPlaying
            ? playbackState.currentNoteIndex
            : sheetState.highlightedNoteIndex;
        final highlightMeasure = playbackState.isPlaying
            ? playbackState.currentMeasure
            : sheetState.highlightedMeasure;

        return SheetMusicWidget(
          sheetData: sheetData,
          highlightedNoteIndex: highlightNote,
          highlightedMeasure: highlightMeasure,
          playbackCursorProgress: _calcCursorProgress(
              playbackState, sheetData),
          transformationController: _transformController,
        );
    }
  }

  void _exportPdf(BuildContext context) {
    ref.read(exportProvider.notifier).exportPdf(
          transcriptionId: widget.transcriptionId,
          title: '樂譜_${widget.transcriptionId.substring(0, 8)}',
        );
  }

  void _exportMidi(BuildContext context) {
    ref.read(exportProvider.notifier).exportMidi(
          transcriptionId: widget.transcriptionId,
          title: '樂譜_${widget.transcriptionId.substring(0, 8)}',
        );
  }

  void _share(BuildContext context) {
    final url = '${Uri.base.origin}/#/sheet/${widget.transcriptionId}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('分享連結: $url')),
    );
  }
}
