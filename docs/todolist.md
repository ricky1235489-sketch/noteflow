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

## Bug 修復記錄（2026-02-13）

### 樂譜與 MIDI 播放不一致
- [x] **`_merge_consecutive_notes` 參數錯誤** — `sheet_generator.py` 傳入 `quarter_duration` 給 `eighth_duration` 參數，導致合併閾值為半音符（應為四分音符），音符被過度合併，時值嚴重偏差
- [x] **MusicXML `<backup>` 修正** — 確保每個小節的 backup 元素總是回退完整小節長度，避免左手音符時間偏移
- [x] **前端 MIDI 解析器左右手分配錯誤** — `midi_parser.dart` 用 track 編號判斷左右手，改為用 pitch >= 60 判斷，與後端 MusicXML 生成邏輯一致
- [x] **Transcription 模型缺少欄位** — 新增 `progress`、`progress_message`、`musicxml_url`、`error` 欄位，與 raw SQL 操作對齊

### 播放游標跳動/不同步
- [x] **OSMD 游標步進效率** — 加入 `_lastCursorMeasure` 去重，避免同一小節重複步進；改用 `endReached` 判斷結束；使用 `cursorElement` 直接捲動
- [x] **PlaybackScheduler 匹配邏輯** — 改為在所有活躍事件中找最近開始的音符，而非第一個匹配；無活躍音符時仍正確追蹤小節位置

### 轉譜品質大幅提升（參考 Pop2Piano arranger 風格）
- [x] **auto 模式不再強制 composer2** — 原本 `audio_to_midi` 的 auto 模式覆蓋 composer 為最簡單的 `composer2`，丟失大量旋律。改為尊重上層傳入的 composer 參數，預設使用 `top5` 自動選擇最佳風格
- [x] **移除三重量化** — 原管線：Pop2Piano → `_enhanced_cleanup`（量化1）→ `quantize_midi`（量化2）→ MusicXML（量化3），每次量化累積誤差。改為 `_enhanced_cleanup` 只做分手和去重，`quantize_midi` 做唯一一次量化
- [x] **保留原始力度動態** — 原本力度被壓縮到 60-100（40 的範圍），Pop2Piano 精心設計的動態被破壞。改為保留原始 velocity（30-127）
- [x] **放寬同時發聲限制** — 右手 4→6、左手 3→4，保留 Pop2Piano 豐富和弦編曲
- [x] **改善 top5 風格選擇** — 移除 `composer2`（太簡單），改用 `composer4/7/10/15/20` 覆蓋簡潔到豐富的完整範圍
- [x] **改善低音部判斷** — 用 bass_ratio >= 15% 判斷是否需要補充左手，而非簡單的 `any(pitch < 60)`

### UX 流程修正
- [x] **上傳完成後直接開啟樂譜** — 原本導航到首頁，使用者不知道去哪裡看結果。改為直接跳轉到 `/sheet/{id}`
- [x] **處理完成後直接開啟樂譜** — `_ProcessingView` 完成時也直接導航到樂譜頁面
- [x] **修復 HomeScreen AppBar 語法錯誤** — 多餘的 `if (!_isSelectionMode)` 導致選擇模式按鈕消失，重構為清晰的 `if/else` 結構
- [x] **編曲風格用使用者語言** — 移除技術術語（composer2/4/7），改用「🎵 標準」「🎹 豐富」等直覺標籤
- [x] **PlaybackControls 在樂譜未載入時隱藏** — 避免使用者看到無效的播放按鈕
- [x] **歷史卡片移除重複圖標** — subtitle 不再重複顯示狀態圖標，改善資訊層級

### 效能優化
- [x] **後端：模型啟動預載** — Pop2Piano 1.5GB 模型在 API 啟動時背景預載，避免首次請求等待 30-60 秒冷啟動
- [x] **後端：auto 模式用單一 composer** — 原本 auto 測試 5 種風格（5x 推理時間），改為直接使用 `composer4`；使用者選了特定風格也直接用
- [x] **後端：降低 beam search 開銷** — `num_beams` 從 3 降到 2（單一推理）/ 1（多風格比較），推理速度提升 ~2-3x
- [x] **前端：MIDI + MusicXML 並行載入** — 原本序列載入（2 個 RTT），改為 `Future.wait` 並行（1 個 RTT）
- [x] **前端：移除 OSMD 200ms 人工延遲** — `Future.delayed(200ms)` 改為 `Future.microtask`
- [x] **前端：精簡鋼琴樣本** — Salamander Piano 從 30 個 HTTP 請求減少到 12 個（Tone.js 自動插值），載入速度提升 ~60%

### 開發體驗 (DX) 改善
- [x] **一鍵啟動腳本 `dev.ps1`** — `.\dev.ps1` 自動安裝依賴、建立 venv、啟動後端和前端，支援 `setup`/`backend`/`frontend` 子指令
- [x] **移除 WSL 依賴** — 後端可直接在 Windows 上跑（SQLite + 本地儲存），不需要 WSL
- [x] **API URL 改為 localhost** — 不再硬編碼 WSL IP（`172.27.106.129`），改為 `localhost:8000`
- [x] **requirements.txt 整理** — torch/transformers/aiosqlite 從「optional」移到主列表，`dev.ps1` 會自動安裝
- [x] **README 重寫** — 清晰的前置需求、一鍵啟動指南、手動啟動步驟

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
