import 'package:flutter/material.dart';
import '../domain/music_note.dart';
import '../domain/rest_note.dart';
import '../domain/sheet_data.dart';

/// 五線譜渲染常數
class StaffConstants {
  StaffConstants._();

  static const double staffLineSpacing = 10.0;
  static const double staffHeight = staffLineSpacing * 4;
  static const double trebleBassGap = 60.0;
  static const double measureWidth = 200.0;
  static const double leftMargin = 80.0; // 加寬以容納調號拍號
  static const double topMargin = 40.0;
  static const double noteRadius = 4.5;
  static const double ledgerLineWidth = 20.0;
  static const double systemHeight = staffHeight * 2 + trebleBassGap;
  static const double systemSpacing = 40.0;
  static const int measuresPerLine = 4;

  /// 計算指定小節所在的 system line Y 座標
  static double systemYForMeasure(int measureIndex) {
    final line = measureIndex ~/ measuresPerLine;
    return topMargin + line * (systemHeight + systemSpacing);
  }
}

/// 五線譜 CustomPainter
class StaffPainter extends CustomPainter {
  final SheetData sheetData;
  final int? highlightedNoteIndex;
  final int? highlightedMeasure;
  final double? playbackCursorProgress;

  StaffPainter({
    required this.sheetData,
    this.highlightedNoteIndex,
    this.highlightedMeasure,
    this.playbackCursorProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (sheetData.measures.isEmpty) return;

    final staffPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final barlinePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5;

    final notePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    final measures = sheetData.measures;
    final totalLines =
        (measures.length / StaffConstants.measuresPerLine).ceil();

    for (var line = 0; line < totalLines; line++) {
      final systemY = StaffConstants.topMargin +
          line * (StaffConstants.systemHeight + StaffConstants.systemSpacing);

      final trebleY = systemY;
      final bassY =
          systemY + StaffConstants.staffHeight + StaffConstants.trebleBassGap;

      _drawStaffLines(canvas, staffPaint, trebleY, size.width);
      _drawStaffLines(canvas, staffPaint, bassY, size.width);
      _drawClefSymbol(canvas, trebleY, isTreble: true);
      _drawClefSymbol(canvas, bassY, isTreble: false);
      _drawBrace(canvas, barlinePaint, trebleY, bassY);

      // 第一行顯示調號和拍號
      if (line == 0) {
        _drawKeySignature(canvas, trebleY, isTreble: true);
        _drawKeySignature(canvas, bassY, isTreble: false);
        _drawTimeSignature(canvas, trebleY);
        _drawTimeSignature(canvas, bassY);
      }

      final startMeasure = line * StaffConstants.measuresPerLine;
      final endMeasure = (startMeasure + StaffConstants.measuresPerLine)
          .clamp(0, measures.length);

      for (var m = startMeasure; m < endMeasure; m++) {
        final measureIndex = m - startMeasure;
        final measureX = StaffConstants.leftMargin +
            measureIndex * StaffConstants.measureWidth;

        final measure = measures[m];
        final isHighlighted = highlightedMeasure == m;

        if (isHighlighted) {
          _drawHighlightedMeasure(
              canvas, measureX, trebleY, bassY);
        }

        if (measureIndex > 0) {
          _drawBarline(canvas, barlinePaint, measureX, trebleY, bassY);
        }

        _drawMeasureNumber(canvas, m + 1, measureX, trebleY - 12);

        _drawNotesInMeasure(
          canvas, measure.trebleNotes, measureX, trebleY,
          notePaint, highlightPaint, isTreble: true,
        );
        _drawNotesInMeasure(
          canvas, measure.bassNotes, measureX, bassY,
          notePaint, highlightPaint, isTreble: false,
        );

        // 繪製休止符
        _drawRestsInMeasure(
          canvas, measure.trebleRests, measure, measureX, trebleY,
        );
        _drawRestsInMeasure(
          canvas, measure.bassRests, measure, measureX, bassY,
        );
      }

      // 結尾小節線
      final endX = StaffConstants.leftMargin +
          (endMeasure - startMeasure) * StaffConstants.measureWidth;
      _drawBarline(canvas, barlinePaint, endX, trebleY, bassY);
    }
  }

  // ─── 高亮小節 + 播放游標 ───

  void _drawHighlightedMeasure(
    Canvas canvas, double measureX, double trebleY, double bassY,
  ) {
    final highlightRect = Rect.fromLTWH(
      measureX,
      trebleY - 5,
      StaffConstants.measureWidth,
      bassY + StaffConstants.staffHeight - trebleY + 10,
    );
    canvas.drawRect(
      highlightRect,
      Paint()..color = Colors.blue.withValues(alpha: 0.08),
    );

    if (playbackCursorProgress != null) {
      final cursorX = measureX +
          playbackCursorProgress!.clamp(0.0, 1.0) *
              StaffConstants.measureWidth;
      final cursorPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.8)
        ..strokeWidth = 2.0;
      canvas.drawLine(
        Offset(cursorX, trebleY - 8),
        Offset(cursorX, bassY + StaffConstants.staffHeight + 8),
        cursorPaint,
      );
      final trianglePath = Path()
        ..moveTo(cursorX - 4, trebleY - 8)
        ..lineTo(cursorX + 4, trebleY - 8)
        ..lineTo(cursorX, trebleY - 3)
        ..close();
      canvas.drawPath(
        trianglePath,
        Paint()
          ..color = Colors.red.withValues(alpha: 0.8)
          ..style = PaintingStyle.fill,
      );
    }
  }

  // ─── 五線譜基礎元素 ───

  void _drawStaffLines(Canvas canvas, Paint paint, double topY, double width) {
    for (var i = 0; i < 5; i++) {
      final y = topY + i * StaffConstants.staffLineSpacing;
      canvas.drawLine(
        Offset(StaffConstants.leftMargin - 10, y),
        Offset(
          StaffConstants.leftMargin +
              StaffConstants.measuresPerLine * StaffConstants.measureWidth,
          y,
        ),
        paint,
      );
    }
  }

  void _drawClefSymbol(Canvas canvas, double topY,
      {required bool isTreble}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: isTreble ? '𝄞' : '𝄢',
        style: TextStyle(
          fontSize: isTreble ? 48 : 36,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final x = StaffConstants.leftMargin - 70;
    final y = isTreble
        ? topY - 8
        : topY + StaffConstants.staffHeight / 2 - textPainter.height / 2;

    textPainter.paint(canvas, Offset(x, y));
  }

  void _drawBrace(
      Canvas canvas, Paint paint, double trebleY, double bassY) {
    final x = StaffConstants.leftMargin - 10;
    canvas.drawLine(
      Offset(x, trebleY),
      Offset(x, bassY + StaffConstants.staffHeight),
      paint,
    );
  }

  void _drawBarline(Canvas canvas, Paint paint, double x,
      double trebleY, double bassY) {
    canvas.drawLine(
      Offset(x, trebleY),
      Offset(x, trebleY + StaffConstants.staffHeight),
      paint,
    );
    canvas.drawLine(
      Offset(x, bassY),
      Offset(x, bassY + StaffConstants.staffHeight),
      paint,
    );
  }

  void _drawMeasureNumber(Canvas canvas, int number, double x, double y) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(x + 2, y));
  }

  // ─── 調號渲染 ───

  void _drawKeySignature(Canvas canvas, double staffTopY,
      {required bool isTreble}) {
    final keySig = sheetData.keySignature;
    if (keySig == 0) return;

    final isSharp = keySig > 0;
    final count = keySig.abs();
    final symbol = isSharp ? '♯' : '♭';

    // 升號在五線譜上的位置順序（F C G D A E B）
    const sharpPositionsTreble = [8, 11, 7, 10, 6, 9, 5]; // F5 C6 G5 D6 A5 E6 B5
    const sharpPositionsBass = [-3, 0, -4, -1, -5, -2, -6];

    // 降號在五線譜上的位置順序（B E A D G C F）
    const flatPositionsTreble = [5, 9, 6, 10, 7, 11, 8];
    const flatPositionsBass = [-6, -2, -5, -1, -4, 0, -3];

    final positions = isSharp
        ? (isTreble ? sharpPositionsTreble : sharpPositionsBass)
        : (isTreble ? flatPositionsTreble : flatPositionsBass);

    final startX = StaffConstants.leftMargin - 42;

    for (var i = 0; i < count && i < positions.length; i++) {
      final staffPos = positions[i];
      final y = _staffPositionToY(staffPos, staffTopY, isTreble);
      final x = startX + i * 10;

      final textPainter = TextPainter(
        text: TextSpan(
          text: symbol,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(x, y - 8));
    }
  }

  // ─── 拍號渲染 ───

  void _drawTimeSignature(Canvas canvas, double staffTopY) {
    final numerator = sheetData.beatsPerMeasure.toString();
    final denominator = sheetData.beatUnit.toString();

    final topPainter = TextPainter(
      text: TextSpan(
        text: numerator,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bottomPainter = TextPainter(
      text: TextSpan(
        text: denominator,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 拍號放在調號右邊、第一小節左邊
    final x = StaffConstants.leftMargin - 18;
    final staffCenter = staffTopY + StaffConstants.staffHeight / 2;

    topPainter.paint(
      canvas,
      Offset(x - topPainter.width / 2, staffCenter - topPainter.height - 1),
    );
    bottomPainter.paint(
      canvas,
      Offset(x - bottomPainter.width / 2, staffCenter + 1),
    );
  }

  // ─── 休止符渲染 ───

  void _drawRestsInMeasure(
    Canvas canvas,
    List<RestNote> rests,
    Measure measure,
    double measureX,
    double staffTopY,
  ) {
    if (rests.isEmpty) return;

    final measureDuration = measure.endTime - measure.startTime;
    final restPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    for (final rest in rests) {
      final relativeTime =
          (rest.startTime - measure.startTime) / measureDuration;
      final restX =
          measureX + 15 + relativeTime * (StaffConstants.measureWidth - 30);
      final staffCenter = staffTopY + StaffConstants.staffHeight / 2;

      switch (rest.type) {
        case RestType.whole:
          _drawWholeRest(canvas, restPaint, restX, staffTopY);
          break;
        case RestType.half:
          _drawHalfRest(canvas, restPaint, restX, staffCenter);
          break;
        case RestType.quarter:
          _drawQuarterRest(canvas, restX, staffCenter);
          break;
        case RestType.eighth:
          _drawEighthRest(canvas, restX, staffCenter);
          break;
        case RestType.sixteenth:
          _drawSixteenthRest(canvas, restX, staffCenter);
          break;
      }
    }
  }

  /// 全休止符：第四線下方的實心矩形（懸掛）
  void _drawWholeRest(
      Canvas canvas, Paint paint, double x, double staffTopY) {
    final lineY = staffTopY + StaffConstants.staffLineSpacing; // 第二線
    canvas.drawRect(
      Rect.fromLTWH(x - 6, lineY, 12, StaffConstants.staffLineSpacing / 2),
      paint,
    );
  }

  /// 二分休止符：第三線上方的實心矩形（坐在線上）
  void _drawHalfRest(
      Canvas canvas, Paint paint, double x, double staffCenter) {
    final lineY = staffCenter; // 第三線
    canvas.drawRect(
      Rect.fromLTWH(
          x - 6, lineY - StaffConstants.staffLineSpacing / 2, 12,
          StaffConstants.staffLineSpacing / 2),
      paint,
    );
  }

  /// 四分休止符：用 Path 繪製 Z 字形符號
  void _drawQuarterRest(Canvas canvas, double x, double staffCenter) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final top = staffCenter - 10;
    final bottom = staffCenter + 10;

    final path = Path()
      ..moveTo(x + 3, top)
      ..lineTo(x - 3, top + 5)
      ..lineTo(x + 3, staffCenter)
      ..lineTo(x - 3, staffCenter + 5)
      ..lineTo(x + 3, bottom);

    canvas.drawPath(path, paint);
  }

  /// 八分休止符：小圓點 + 斜線
  void _drawEighthRest(Canvas canvas, double x, double staffCenter) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    // 斜線
    canvas.drawLine(
      Offset(x + 2, staffCenter - 6),
      Offset(x - 3, staffCenter + 6),
      paint,
    );
    // 圓點
    canvas.drawCircle(Offset(x + 2, staffCenter - 6), 2.0, dotPaint);
  }

  /// 十六分休止符：兩個圓點 + 斜線
  void _drawSixteenthRest(Canvas canvas, double x, double staffCenter) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;

    canvas.drawLine(
      Offset(x + 2, staffCenter - 9),
      Offset(x - 4, staffCenter + 6),
      paint,
    );
    canvas.drawCircle(Offset(x + 2, staffCenter - 9), 2.0, dotPaint);
    canvas.drawCircle(Offset(x + 0, staffCenter - 3), 2.0, dotPaint);
  }

  // ─── 音符渲染 ───

  void _drawNotesInMeasure(
    Canvas canvas,
    List<MusicNote> notes,
    double measureX,
    double staffTopY,
    Paint notePaint,
    Paint highlightPaint, {
    required bool isTreble,
  }) {
    if (notes.isEmpty) return;

    final measure = sheetData.measures.firstWhere(
      (m) => (isTreble ? m.trebleNotes : m.bassNotes) == notes,
      orElse: () => sheetData.measures.first,
    );
    final measureDuration = measure.endTime - measure.startTime;

    for (final note in notes) {
      final relativeTime =
          (note.startTime - measure.startTime) / measureDuration;
      final noteX = measureX +
          15 +
          relativeTime * (StaffConstants.measureWidth - 30);
      final staffPosition = note.staffPosition;
      final noteY = _staffPositionToY(staffPosition, staffTopY, isTreble);

      final isHighlighted = highlightedNoteIndex != null &&
          sheetData.allNotes.indexOf(note) == highlightedNoteIndex;
      final paint = isHighlighted ? highlightPaint : notePaint;

      // 音符頭
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(noteX, noteY),
          width: StaffConstants.noteRadius * 2.2,
          height: StaffConstants.noteRadius * 1.8,
        ),
        paint,
      );

      // 符桿
      final stemUp = staffPosition < 4;
      final stemX = stemUp
          ? noteX + StaffConstants.noteRadius
          : noteX - StaffConstants.noteRadius;
      final stemEndY = stemUp ? noteY - 30 : noteY + 30;
      canvas.drawLine(
        Offset(stemX, noteY),
        Offset(stemX, stemEndY),
        Paint()
          ..color = paint.color
          ..strokeWidth = 1.2,
      );

      _drawLedgerLines(canvas, noteX, noteY, staffTopY, isTreble);

      if (note.isSharp) {
        final sharpPainter = TextPainter(
          text: TextSpan(
            text: '♯',
            style: TextStyle(fontSize: 12, color: paint.color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        sharpPainter.paint(canvas, Offset(noteX - 14, noteY - 8));
      }
    }
  }

  double _staffPositionToY(
      int staffPosition, double staffTopY, bool isTreble) {
    final referencePosition = isTreble ? 10 : -5;
    final referenceY = staffTopY;
    final halfSpacing = StaffConstants.staffLineSpacing / 2;
    return referenceY + (referencePosition - staffPosition) * halfSpacing;
  }

  void _drawLedgerLines(
    Canvas canvas,
    double noteX,
    double noteY,
    double staffTopY,
    bool isTreble,
  ) {
    final staffBottom = staffTopY + StaffConstants.staffHeight;
    final ledgerPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 1.0;
    final halfWidth = StaffConstants.ledgerLineWidth / 2;

    if (noteY < staffTopY) {
      var y = staffTopY - StaffConstants.staffLineSpacing;
      while (y >= noteY - 2) {
        canvas.drawLine(
          Offset(noteX - halfWidth, y),
          Offset(noteX + halfWidth, y),
          ledgerPaint,
        );
        y -= StaffConstants.staffLineSpacing;
      }
    }

    if (noteY > staffBottom) {
      var y = staffBottom + StaffConstants.staffLineSpacing;
      while (y <= noteY + 2) {
        canvas.drawLine(
          Offset(noteX - halfWidth, y),
          Offset(noteX + halfWidth, y),
          ledgerPaint,
        );
        y += StaffConstants.staffLineSpacing;
      }
    }

    if (isTreble &&
        (noteY - staffBottom).abs() < StaffConstants.staffLineSpacing) {
      canvas.drawLine(
        Offset(noteX - halfWidth,
            staffBottom + StaffConstants.staffLineSpacing),
        Offset(noteX + halfWidth,
            staffBottom + StaffConstants.staffLineSpacing),
        ledgerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StaffPainter oldDelegate) {
    return oldDelegate.sheetData != sheetData ||
        oldDelegate.highlightedNoteIndex != highlightedNoteIndex ||
        oldDelegate.highlightedMeasure != highlightedMeasure ||
        oldDelegate.playbackCursorProgress != playbackCursorProgress;
  }
}
