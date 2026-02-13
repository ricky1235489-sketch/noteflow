# Technical Design: NoteFlow

## 技術架構詳細設計

### 1. 行動端（Flutter App）

#### 專案結構

```
noteflow_app/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── constants/
│   │   │   └── app_constants.dart
│   │   ├── errors/
│   │   │   └── failures.dart
│   │   ├── network/
│   │   │   └── api_client.dart
│   │   └── theme/
│   │       └── app_theme.dart
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── auth_repository_impl.dart
│   │   │   │   └── auth_remote_datasource.dart
│   │   │   ├── domain/
│   │   │   │   ├── auth_repository.dart
│   │   │   │   └── user_entity.dart
│   │   │   └── presentation/
│   │   │       ├── login_screen.dart
│   │   │       └── auth_provider.dart
│   │   ├── transcription/
│   │   │   ├── data/
│   │   │   │   ├── transcription_repository_impl.dart
│   │   │   │   └── transcription_remote_datasource.dart
│   │   │   ├── domain/
│   │   │   │   ├── transcription_repository.dart
│   │   │   │   ├── transcription_entity.dart
│   │   │   │   └── use_cases/
│   │   │   │       ├── upload_audio.dart
│   │   │   │       └── get_transcription.dart
│   │   │   └── presentation/
│   │   │       ├── home_screen.dart
│   │   │       ├── transcription_screen.dart
│   │   │       ├── sheet_music_viewer.dart
│   │   │       └── transcription_provider.dart
│   │   ├── playback/
│   │   │   ├── data/
│   │   │   │   └── soundfont_loader.dart
│   │   │   ├── domain/
│   │   │   │   ├── playback_state.dart
│   │   │   │   └── midi_parser.dart
│   │   │   └── presentation/
│   │   │       ├── playback_controls.dart
│   │   │       ├── playback_provider.dart
│   │   │       └── tempo_slider.dart
│   │   └── settings/
│   │       └── presentation/
│   │           └── settings_screen.dart
│   └── shared/
│       ├── widgets/
│       │   ├── loading_overlay.dart
│       │   └── error_dialog.dart
│       └── services/
│           ├── audio_recorder_service.dart
│           ├── file_picker_service.dart
│           └── midi_playback_service.dart
├── test/
├── pubspec.yaml
└── README.md
```

#### 狀態管理

使用 Riverpod 進行狀態管理：

```dart
// 轉譜狀態
enum TranscriptionStatus { idle, uploading, processing, completed, failed }

class TranscriptionState {
  final TranscriptionStatus status;
  final TranscriptionEntity? result;
  final String? errorMessage;
  final double progress;

  const TranscriptionState({
    this.status = TranscriptionStatus.idle,
    this.result,
    this.errorMessage,
    this.progress = 0.0,
  });

  TranscriptionState copyWith({...}) => TranscriptionState(...);
}
```

#### 樂譜渲染引擎

使用 CustomPainter 自建五線譜渲染：

```dart
class SheetMusicPainter extends CustomPainter {
  final List<MusicNote> notes;
  final TimeSignature timeSignature;
  final KeySignature keySignature;

  // 渲染五線譜線條
  // 渲染音符（全音符、二分、四分、八分、十六分）
  // 渲染休止符
  // 渲染調號、拍號
  // 渲染小節線
}
```

#### 樂譜播放引擎

使用 `flutter_midi_pro` + SoundFont 進行本地 MIDI 合成播放：

```dart
/// 播放狀態
enum PlaybackStatus { stopped, playing, paused }

class PlaybackState {
  final PlaybackStatus status;
  final Duration currentPosition;
  final Duration totalDuration;
  final double tempoMultiplier;
  final int currentNoteIndex;
  final int currentMeasure;

  const PlaybackState({
    this.status = PlaybackStatus.stopped,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.tempoMultiplier = 1.0,
    this.currentNoteIndex = 0,
    this.currentMeasure = 0,
  });

  PlaybackState copyWith({...}) => PlaybackState(...);
}
```

```dart
/// MIDI 播放服務
class MidiPlaybackService {
  final FlutterMidiPro _midiPro = FlutterMidiPro();
  bool _soundFontLoaded = false;

  /// 載入鋼琴 SoundFont（app 啟動時預載）
  Future<void> loadSoundFont() async {
    final sf2Data = await rootBundle.load('assets/soundfonts/piano.sf2');
    await _midiPro.loadSoundfont(sf2: sf2Data);
    _soundFontLoaded = true;
  }

  /// 播放單一音符
  Future<void> playNote({
    required int midiNote,
    required int velocity,
    required int channel,
  }) async {
    assert(_soundFontLoaded, 'SoundFont 尚未載入');
    await _midiPro.playNote(
      channel: channel,
      key: midiNote,
      velocity: velocity,
    );
  }

  /// 停止單一音符
  Future<void> stopNote({
    required int midiNote,
    required int channel,
  }) async {
    await _midiPro.stopNote(channel: channel, key: midiNote);
  }

  /// 停止所有音符
  Future<void> stopAllNotes() async {
    for (int channel = 0; channel < 16; channel++) {
      for (int note = 0; note < 128; note++) {
        await _midiPro.stopNote(channel: channel, key: note);
      }
    }
  }
}
```

```dart
/// 樂譜播放排程器 — 根據 MIDI 事件時間軸驅動播放與高亮
class PlaybackScheduler {
  final MidiPlaybackService _playbackService;
  final List<TimedMidiEvent> _events;
  Timer? _timer;
  int _currentEventIndex = 0;
  double _tempoMultiplier = 1.0;

  /// 開始播放
  void play() {
    _scheduleNextEvent();
  }

  /// 暫停（保留位置）
  void pause() {
    _timer?.cancel();
    _playbackService.stopAllNotes();
  }

  /// 跳轉至指定小節
  void seekToMeasure(int measureNumber) {
    _timer?.cancel();
    _playbackService.stopAllNotes();
    _currentEventIndex = _findEventIndexForMeasure(measureNumber);
    _scheduleNextEvent();
  }

  /// 調整速度（0.25x ~ 2.0x）
  void setTempo(double multiplier) {
    assert(multiplier >= 0.25 && multiplier <= 2.0);
    _tempoMultiplier = multiplier;
  }

  void _scheduleNextEvent() {
    if (_currentEventIndex >= _events.length) return;

    final event = _events[_currentEventIndex];
    final delay = Duration(
      milliseconds: (event.deltaMs / _tempoMultiplier).round(),
    );

    _timer = Timer(delay, () {
      _playbackService.playNote(
        midiNote: event.note,
        velocity: event.velocity,
        channel: 0,
      );
      // 通知 UI 高亮當前音符
      onNoteHighlight?.call(event.noteIndex, event.measure);
      _currentEventIndex++;
      _scheduleNextEvent();
    });
  }
}
```

SoundFont 選擇：打包一個精簡的鋼琴 SoundFont（約 5–15MB），放在 `assets/soundfonts/piano.sf2`。推薦使用 FluidR3 GM 的鋼琴子集，音質好且體積可控。

#### 播放與樂譜同步機制

```
播放引擎                          樂譜渲染器
   │                                  │
   │  onNoteHighlight(noteIdx, bar)   │
   ├─────────────────────────────────►│
   │                                  │ 高亮對應音符
   │                                  │ 自動捲動至當前小節
   │                                  │
   │  使用者點擊小節 N                  │
   │◄─────────────────────────────────┤
   │  seekToMeasure(N)                │
   │  從小節 N 開始播放                │
```

### 2. 後端（FastAPI）

#### 專案結構

```
noteflow_api/
├── app/
│   ├── main.py
│   ├── config.py
│   ├── dependencies.py
│   ├── api/
│   │   ├── v1/
│   │   │   ├── router.py
│   │   │   ├── auth.py
│   │   │   ├── transcriptions.py
│   │   │   └── upload.py
│   ├── core/
│   │   ├── security.py
│   │   ├── rate_limiter.py
│   │   └── exceptions.py
│   ├── models/
│   │   ├── user.py
│   │   └── transcription.py
│   ├── schemas/
│   │   ├── auth.py
│   │   ├── transcription.py
│   │   └── common.py
│   ├── services/
│   │   ├── auth_service.py
│   │   ├── transcription_service.py
│   │   ├── audio_processor.py
│   │   ├── midi_converter.py
│   │   └── sheet_generator.py
│   └── repositories/
│       ├── user_repository.py
│       └── transcription_repository.py
├── tests/
├── alembic/
├── requirements.txt
├── Dockerfile
└── docker-compose.yml
```

#### 轉譜服務核心邏輯

```python
class TranscriptionService:
    """音訊轉譜核心服務"""

    async def transcribe(self, audio_file_key: str, user_id: str) -> TranscriptionResult:
        # 1. 從 S3 下載音訊
        audio_path = await self.storage.download(audio_file_key)

        # 2. 使用 Basic Pitch 進行音高偵測
        midi_data = await self.audio_processor.extract_notes(audio_path)

        # 3. 量化與清理 MIDI 資料
        quantized_midi = self.midi_converter.quantize(midi_data)

        # 4. 分離左右手（高音/低音譜號）
        treble, bass = self.midi_converter.split_hands(quantized_midi)

        # 5. 產生 MusicXML
        musicxml = self.sheet_generator.to_musicxml(treble, bass)

        # 6. 產生 PDF
        pdf_bytes = self.sheet_generator.to_pdf(musicxml)

        # 7. 上傳結果至 S3
        midi_url = await self.storage.upload(midi_data, f"{user_id}/midi/")
        xml_url = await self.storage.upload(musicxml, f"{user_id}/xml/")
        pdf_url = await self.storage.upload(pdf_bytes, f"{user_id}/pdf/")

        return TranscriptionResult(
            midi_url=midi_url,
            musicxml_url=xml_url,
            pdf_url=pdf_url,
        )
```

#### Basic Pitch 整合

```python
class AudioProcessor:
    """使用 Spotify Basic Pitch 進行音訊分析"""

    def __init__(self):
        from basic_pitch.inference import predict

        self.predict = predict

    async def extract_notes(self, audio_path: str) -> MidiData:
        model_output, midi_data, note_events = self.predict(audio_path)

        return MidiData(
            midi=midi_data,
            note_events=note_events,
            onset_threshold=0.5,
            frame_threshold=0.3,
        )
```

#### 左右手分離演算法

```python
class MidiConverter:
    SPLIT_NOTE = 60  # Middle C (C4) 作為分割點

    def split_hands(self, midi_data: QuantizedMidi) -> tuple[list, list]:
        """根據音高將音符分配至高音譜號（右手）與低音譜號（左手）"""
        treble_notes = []
        bass_notes = []

        for note in midi_data.notes:
            if note.pitch >= self.SPLIT_NOTE:
                treble_notes = [*treble_notes, note]
            else:
                bass_notes = [*bass_notes, note]

        return treble_notes, bass_notes
```

### 3. 非同步任務處理

使用 Celery + Redis 處理耗時的轉譜任務：

```python
# 任務佇列
@celery_app.task(bind=True, max_retries=3)
def process_transcription(self, transcription_id: str, audio_file_key: str):
    try:
        service = TranscriptionService()
        result = service.transcribe(audio_file_key, transcription_id)
        update_transcription_status(transcription_id, "completed", result)
    except Exception as exc:
        update_transcription_status(transcription_id, "failed", str(exc))
        raise self.retry(exc=exc, countdown=60)
```

### 4. 檔案上傳流程

使用 S3 Presigned URL 進行安全上傳：

```python
async def generate_upload_url(user_id: str, filename: str) -> PresignedUrlResponse:
    allowed_extensions = {".mp3", ".wav", ".m4a"}
    file_extension = Path(filename).suffix.lower()

    if file_extension not in allowed_extensions:
        raise ValidationError(f"不支援的檔案格式: {file_extension}")

    file_key = f"uploads/{user_id}/{uuid4()}{file_extension}"

    presigned_url = s3_client.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": settings.S3_BUCKET,
            "Key": file_key,
            "ContentType": MIME_TYPES[file_extension],
        },
        ExpiresIn=3600,
    )

    return PresignedUrlResponse(upload_url=presigned_url, file_key=file_key)
```

### 5. Rate Limiting 實作

```python
class RateLimiter:
    LIMITS = {
        "free": {"monthly_conversions": 3, "max_duration_seconds": 30},
        "pro": {"monthly_conversions": 999999, "max_duration_seconds": 600},
    }

    async def check_limit(self, user: User) -> bool:
        limits = self.LIMITS[user.subscription_tier]

        if user.monthly_conversions_used >= limits["monthly_conversions"]:
            raise RateLimitExceeded("已達本月轉換上限")

        return True
```

### 6. 部署架構

```
Production:
├── AWS ECS (or Railway)
│   ├── FastAPI container (2+ instances, auto-scaling)
│   ├── Celery worker container (GPU-enabled for ML)
│   └── Redis container (task queue + caching)
├── AWS RDS PostgreSQL
├── AWS S3 (audio + generated files)
├── CloudFront CDN (static assets + PDF delivery)
└── Firebase (Auth)

Development:
├── Docker Compose (all services local)
├── LocalStack (S3 mock)
└── SQLite (local DB alternative)
```

### 7. 監控與日誌

- Sentry：錯誤追蹤
- CloudWatch / Datadog：效能監控
- Structured logging（JSON 格式）
- 轉譜成功率追蹤
- API 回應時間監控
