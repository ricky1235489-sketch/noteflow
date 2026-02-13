class AppConstants {
  AppConstants._();

  static const String appName = 'NoteFlow';

  // API — auto-detect: works with both localhost and WSL
  // When running backend on Windows (.\dev.ps1), use localhost.
  // When running backend in WSL, change to your WSL IP.
  // Flutter web runs in browser, so "localhost" = the machine serving the page.
  static const String apiBaseUrl = 'http://localhost:8000/api/v1';

  // Audio
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB
  static const List<String> allowedAudioExtensions = ['mp3', 'wav', 'm4a'];
  static const int freeMaxDurationSeconds = 30;
  static const int proMaxDurationSeconds = 600;

  // Playback
  static const double minTempoMultiplier = 0.25;
  static const double maxTempoMultiplier = 2.0;
  static const double defaultTempoMultiplier = 1.0;
  static const String soundFontAssetPath = 'assets/soundfonts/piano.sf2';

  // Subscription
  static const int freeMonthlyConversions = 3;

  // RevenueCat (replace with your actual API key)
  static const String revenueCatApiKey = 'YOUR_REVENUECAT_API_KEY';
}
