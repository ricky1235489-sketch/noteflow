enum TranscriptionStatus { pending, processing, completed, failed }

class TranscriptionEntity {
  final String id;
  final String title;
  final TranscriptionStatus status;
  final String? originalAudioUrl;
  final String? midiUrl;
  final String? pdfUrl;
  final String? musicXmlUrl;
  final double? durationSeconds;
  final DateTime createdAt;
  final DateTime? completedAt;
  final int progress; // 0-100
  final String progressMessage;

  const TranscriptionEntity({
    required this.id,
    required this.title,
    required this.status,
    this.originalAudioUrl,
    this.midiUrl,
    this.pdfUrl,
    this.musicXmlUrl,
    this.durationSeconds,
    required this.createdAt,
    this.completedAt,
    this.progress = 0,
    this.progressMessage = "Waiting",
  });

  bool get isCompleted => status == TranscriptionStatus.completed;
  bool get isProcessing =>
      status == TranscriptionStatus.pending ||
      status == TranscriptionStatus.processing;
  bool get isFailed => status == TranscriptionStatus.failed;
}
