import 'package:flutter/material.dart';
import '../domain/sheet_data.dart';
import 'staff_painter.dart';

/// 可捲動的五線譜顯示元件
class SheetMusicWidget extends StatelessWidget {
  final SheetData sheetData;
  final int? highlightedNoteIndex;
  final int? highlightedMeasure;
  final double? playbackCursorProgress;
  final TransformationController? transformationController;

  const SheetMusicWidget({
    super.key,
    required this.sheetData,
    this.highlightedNoteIndex,
    this.highlightedMeasure,
    this.playbackCursorProgress,
    this.transformationController,
  });

  @override
  Widget build(BuildContext context) {
    if (sheetData.measures.isEmpty) {
      return const Center(
        child: Text('沒有音符資料'),
      );
    }

    final totalLines =
        (sheetData.measures.length / StaffConstants.measuresPerLine).ceil();
    final totalHeight = StaffConstants.topMargin +
        totalLines *
            (StaffConstants.systemHeight + StaffConstants.systemSpacing) +
        StaffConstants.topMargin;
    final totalWidth = StaffConstants.leftMargin +
        StaffConstants.measuresPerLine * StaffConstants.measureWidth +
        20;

    return InteractiveViewer(
      transformationController: transformationController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(20),
      minScale: 0.5,
      maxScale: 3.0,
      child: CustomPaint(
        size: Size(totalWidth, totalHeight),
        painter: StaffPainter(
          sheetData: sheetData,
          highlightedNoteIndex: highlightedNoteIndex,
          highlightedMeasure: highlightedMeasure,
          playbackCursorProgress: playbackCursorProgress,
        ),
      ),
    );
  }
}
