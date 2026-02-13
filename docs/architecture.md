# Architecture: NoteFlow

## 系統架構總覽

```
┌─────────────────────────────────────────────────┐
│                 Mobile App (Flutter)             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐│
│  │ Audio    │ │ Sheet    │ │ Playback │ │ User ││
│  │ Input    │ │ Music    │ │ Engine   │ │ Mgmt ││
│  │ Module   │ │ Renderer │ │ (MIDI    │ │Module││
│  │          │ │          │ │  Synth)  │ │      ││
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──┬───┘│
│       │             │            │           │   │
│       └─────────┬───┘────────────┘───────────┘   │
│                   │                              │
│            ┌──────┴──────┐                       │
│            │  API Client │                       │
│            └──────┬──────┘                       │
└───────────────────┼──────────────────────────────┘
                    │ HTTPS
┌───────────────────┼──────────────────────────────┐
│           Backend (FastAPI + Python)              │
│                   │                              │
│  ┌────────────────┴────────────────────────┐     │
│  │            API Gateway                  │     │
│  │  (Auth, Rate Limiting, Validation)      │     │
│  └──┬──────────┬──────────────┬────────────┘     │
│     │          │              │                   │
│  ┌──┴───┐  ┌──┴──────┐  ┌───┴─────────┐         │
│  │ Auth │  │ Transc. │  │ Sheet Music │         │
│  │ Svc  │  │ Service │  │ Service     │         │
│  └──┬───┘  └──┬──────┘  └───┬─────────┘         │
│     │         │              │                   │
│     │    ┌────┴─────┐   ┌───┴──────┐            │
│     │    │ Basic    │   │ MIDI to  │            │
│     │    │ Pitch ML │   │ Notation │            │
│     │    └──────────┘   └──────────┘            │
│     │                                            │
│  ┌──┴──────────────────────────────────┐         │
│  │         Data Layer                  │         │
│  │  PostgreSQL  │  S3 (Audio/PDF)      │         │
│  └─────────────────────────────────────┘         │
└──────────────────────────────────────────────────┘
```

## 技術選型

| 層級 | 技術 | 理由 |
|------|------|------|
| Mobile | Flutter (Dart) | 跨平台、單一程式碼庫、優秀的 UI 渲染 |
| Backend | Python + FastAPI | ML 生態系最佳、非同步支援、自動 API 文件 |
| ML Model | Spotify Basic Pitch | 開源 MIT、多音軌轉錄、準確度高 |
| MIDI Playback | flutter_midi_pro + SoundFont | 行動端 MIDI 合成播放、鋼琴音色 |
| Sheet Rendering | flutter_music_notation (自建) | 行動端原生渲染五線譜 |
| Database | PostgreSQL | 可靠、JSON 支援、全文搜尋 |
| File Storage | AWS S3 / Cloudflare R2 | 低成本物件儲存 |
| Auth | Firebase Auth | 快速整合、社群登入支援 |
| Payments | RevenueCat | 跨平台訂閱管理、App Store/Play Store 整合 |
| Hosting | AWS ECS or Railway | 容器化部署、自動擴展 |

## 核心資料流

### 音樂轉譜流程

```
1. 使用者上傳音訊 / 錄音
2. App 將音訊檔上傳至 S3，取得 file_key
3. App 呼叫 POST /api/v1/transcriptions
4. Backend 從 S3 下載音訊
5. Basic Pitch 模型處理音訊 → 產生 MIDI 資料
6. MIDI 資料轉換為 MusicXML 格式
7. 產生 PDF 樂譜，上傳至 S3
8. 回傳結果（MIDI + MusicXML + PDF URL）至 App
9. App 渲染五線譜顯示
10. App 下載 MIDI 檔案至本地快取
11. 使用者點擊播放 → MIDI Synth 載入 SoundFont 並播放
12. 播放時同步高亮當前音符位置於樂譜上
```

## API 設計

### 核心端點

```
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh

POST   /api/v1/transcriptions          # 建立轉譜任務
GET    /api/v1/transcriptions           # 列出歷史記錄
GET    /api/v1/transcriptions/{id}      # 取得單一結果
DELETE /api/v1/transcriptions/{id}      # 刪除記錄

POST   /api/v1/upload/audio             # 上傳音訊檔
GET    /api/v1/export/{id}/pdf          # 匯出 PDF
GET    /api/v1/export/{id}/midi         # 匯出 MIDI

GET    /api/v1/users/me                 # 使用者資訊
GET    /api/v1/users/me/usage           # 使用量統計
```

## 資料庫 Schema

### users
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    firebase_uid VARCHAR(128) UNIQUE NOT NULL,
    display_name VARCHAR(100),
    subscription_tier VARCHAR(20) DEFAULT 'free',
    monthly_conversions_used INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### transcriptions
```sql
CREATE TABLE transcriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    original_audio_url TEXT NOT NULL,
    midi_url TEXT,
    musicxml_url TEXT,
    pdf_url TEXT,
    duration_seconds FLOAT,
    status VARCHAR(20) DEFAULT 'pending',
    difficulty_level VARCHAR(20) DEFAULT 'original',
    created_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);
```

## 安全性考量

- 所有 API 端點需 JWT 認證（除 auth 相關）
- 音訊檔上傳限制：50MB、僅允許 MP3/WAV/M4A
- Rate limiting：Free 用戶 3 次/月，Pro 用戶 100 次/天
- S3 presigned URLs 用於檔案存取（過期時間 1 小時）
- 輸入驗證使用 Pydantic schemas
- CORS 僅允許 App 來源
