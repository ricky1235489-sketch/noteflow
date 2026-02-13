import 'package:flutter/material.dart';

/// Stub for non-web platforms - OSMD only works on web
class OsmdSheetWidget extends StatelessWidget {
  final String musicXml;
  final String? title;
  final double? currentTime;
  final VoidCallback? onReady;

  const OsmdSheetWidget({
    super.key,
    required this.musicXml,
    this.title,
    this.currentTime,
    this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    // On non-web platforms, show a message
    return const Center(
      child: Text('OSMD 僅支援 Web 平台'),
    );
  }
}
