# NoteFlow — 開發任務清單

## Phase 1: MVP

### 後端基礎建設
- [x] 初始化 FastAPI 專案結構
- [x] 設定 Docker + docker-compose 開發環境 — Dockerfile + docker-compose.yml（api, db, redis, worker）
- [x] 設定 PostgreSQL + Alembic migrations — SQLAlchemy async + aiosqlite（dev）/ asyncpg（prod），Alembic 設定完成
- [x] 實作 config.py（環境變數管理）
- [x] 實作共用 API 回應格式（ApiResponse schema）

### 認證系統
- [x] 整合 Firebase Auth（JWT 驗證）— python-jose 解碼，dev mode 跳過簽名驗證
- [x] 實作 auth middleware — get_current_user / get_optional_user FastAPI dependencies
- [x] 實作 POST /api/v1/auth/register — 建立使用者，防重複
- [x] 實作 POST /api/v1/auth/login — 自動註冊首次登入使用者
- [x] 實作 GET /api/v1/users/me — 取得當前使用者資料（需 Bearer token）

### 檔案上傳
- [x] 設定 S3 / Cloudflare R2 連線（MVP 使用本地儲存）
- [x] 實作 presigned URL 產生
- [x] 實作 POST /api/v1/upload/audio
- [x] 檔案格式驗證（MP3、WAV、M4A）
- [x] 檔案大小限制（50MB）

### 轉譜核心引擎
- [x] 整合 Spotify Basic Pitch 模型（已安裝，但 Python 3.13 缺 TensorFlow，使用 demo fallback）
- [x] 實作 AudioProcessor（音訊 → MIDI，含 demo fallback）
- [x] 實作 MidiConverter（MIDI 量化 + 左右手分離）
- [x] 實作 SheetGenerator（MIDI → MusicXML）
- [x] 實作 PDF 產生（MusicXML → PDF，需 LilyPond）
- [x] 設定 Celery + Redis 非同步任務佇列 — celery_app + transcribe_audio task
- [x] 實作 ChordDetector（和弦偵測，模板匹配 major/minor/dim/aug/sus/7th）
- [x] 實作 ArrangementPatterns（12 種左手伴奏型態 + NicePianoSheet 風格自適應選擇）
  - 基礎型態：broken_chord, alberti_bass, octave_root, block_chord, arpeggio_up, root_fifth
  - 進階型態：stride, walking_bass, oom_pah, ostinato
  - NicePianoSheet 風格：power_octave（八度低音+和弦填充）, tremolo_chord（震音和弦）
  - ADAPTIVE 模式：根據段落位置、音符密度、力度、速度自動選擇最適型態
  - 段落過渡偵測 + velocity 漸變（模擬自然演奏動態）

### 轉譜 API
- [x] 實作 POST /api/v1/transcriptions
- [x] 實作 GET /api/v1/transcriptions
- [x] 實作 GET /api/v1/transcriptions/{id}
- [x] 實作 DELETE /api/v1/transcriptions/{id}
- [x] 實作 GET /api/v1/transcriptions/{id}/pdf（匯出 PDF）
- [x] 實作 GET /api/v1/transcriptions/{id}/midi（匯出 MIDI）

### Rate Limiting
- [x] 實作使用量追蹤（monthly_conversions_used）
- [x] Free 用戶：3 次/月、30 秒限制
- [x] Pro 用戶：無限次、10 分鐘限制
- [x] 實作 GET /api/v1/users/me/usage

### Flutter App 基礎
- [x] 初始化 Flutter 專案
- [x] 設定 Riverpod 狀態管理
- [x] 設定 API Client（Dio）
- [x] 設定路由（GoRouter）
- [x] 設定主題與設計系統

### App — 認證功能
- [x] 登入畫面 UI — LoginScreen（Email/密碼表單 + 訪客模式按鈕）
- [x] 註冊畫面 UI — 同一頁面切換登入/註冊模式
- [x] Firebase Auth 整合 — firebase_core + firebase_auth，Web SDK 載入，authStateChanges 監聽
- [x] Token 管理與自動刷新 — AuthNotifier 自動同步後端，apiClientProvider 自動注入 token
- [x] 訪客模式 — guestModeProvider 允許未登入使用基本功能
- [x] 用戶選單 — HomeScreen 右上角頭像，顯示帳號資訊/訂閱狀態/登出

### App — 首頁與上傳
- [x] 首頁 UI（歷史記錄列表）
- [x] 檔案選擇器（從裝置選擇音訊）— file_picker 整合完成
- [x] 麥克風錄音功能
- [x] 上傳進度顯示
- [x] 前後端串接（API Client → 後端上傳 + 轉譜）

### App — 樂譜顯示
- [x] 五線譜渲染引擎（CustomPainter）— StaffPainter 實作完成
- [x] 音符渲染（全音符至十六分音符）— 音符頭、符桿、加線
- [x] 休止符渲染 — RestNote model + StaffPainter 繪製全/二分/四分/八分/十六分休止符
- [x] 調號與拍號顯示 — 升降號渲染 + 拍號數字顯示，MidiParser 提取 Time Signature meta event
- [x] 小節線與終止線 — 含小節號、大括號
- [x] 捲動與縮放手勢 — InteractiveViewer（平移 + 縮放 0.5x~3x）

### App — 樂譜播放
- [x] 整合音訊合成引擎 — Web Audio API（flutter_midi_pro 不支援 web，改用 WebAudioService）
- [x] 鋼琴音色合成（基頻 + 泛音 + ADSR envelope）— 取代 SoundFont
- [x] 實作 MidiPlaybackService（音符播放/停止）— WebAudioService 包裝
- [x] 實作 MIDI 檔案解析器（提取帶時間軸的音符事件）— MidiParser 完成
- [x] 實作 PlaybackScheduler（事件排程、計時器驅動）— ~60fps Timer tick
- [x] 播放控制 UI（播放 / 暫停 / 停止按鈕）— PlaybackControls
- [x] 播放進度條 + 拖曳跳轉 — Slider + seekTo
- [x] 播放時音符即時高亮（同步渲染器）— PlaybackNotifier → SheetMusicWidget
- [x] 播放時自動捲動樂譜至當前小節 — TransformationController + system line 追蹤
- [x] 速度調整滑桿（0.25x ~ 2.0x）— TempoSlider
- [x] 點擊小節跳轉播放位置 — seekToMeasure

### App — 匯出功能
- [x] PDF 下載與分享 — ExportService + 瀏覽器下載（data URL + AnchorElement）
- [x] MIDI 檔案下載 — 同上
- [x] 系統分享功能整合 — Web 端複製連結（TODO: 行動端用 share_plus）

### 付費功能
- [x] 整合 RevenueCat SDK
- [x] 設定 App Store / Play Store 訂閱商品
- [x] 實作付費牆 UI
- [x] 訂閱狀態同步至後端

---

## 待辦提醒

### Firebase 設定（認證功能啟用前必須完成）
1. 前往 [Firebase Console](https://console.firebase.google.com) 建立專案
2. 新增「網頁應用程式」，取得 config
3. 將 config 貼到 `noteflow_app/web/index.html` 替換 placeholder（`YOUR_API_KEY` 等）
4. 在 Firebase Console → Authentication → Sign-in method 啟用「Email/密碼」
5. （選用）啟用 Google 登入等其他登入方式
6. 將 `firebase_project_id` 設定到後端 `.env`（正式環境需要驗證 JWT 簽名）

> 訪客模式不需要 Firebase 設定即可使用。

---

## 已知限制

- ~~Python 3.13 不支援 basic-pitch 所需的 TensorFlow~~ → 已安裝 Python 3.12 venv，TensorFlow + basic-pitch 正常運作
- PDF 產生需要安裝 LilyPond，目前 fallback 為 MusicXML
- 後端啟動指令：`noteflow_api\.venv312\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000`（需在 noteflow_api 目錄下執行）

---

## Phase 2: 進階功能

### 難度調整
- [ ] 初級版本自動簡化演算法
- [ ] 中級版本編排
- [ ] 難度選擇 UI

### 和弦辨識
- [x] 和弦偵測演算法 — ChordDetector 模板匹配，支援 9 種和弦類型
- [ ] 和弦符號渲染於譜表上方

### 練習模式進階
- [ ] A-B 段落循環（選取起點終點反覆播放）
- [ ] 左手/右手分別播放切換
- [ ] 節拍器疊加播放

### 歌詞對齊
- [ ] 人聲偵測與分離
- [ ] 歌詞時間軸對齊
- [ ] 歌詞渲染於樂譜下方

---

## Phase 3: 社群與擴展

- [ ] 樂譜分享功能
- [ ] 樂譜編輯器
- [ ] 多樂器支援
- [ ] 社群探索頁面
