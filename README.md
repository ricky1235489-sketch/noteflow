# NoteFlow

將音樂檔案轉換為鋼琴樂譜的跨平台應用程式。

## 專案結構

- `noteflow_app/` — Flutter 前端（Web / Mobile）
- `noteflow_api/` — FastAPI 後端（音訊處理 + 轉譜引擎）
- `docs/` — 產品需求、架構設計、技術文件

## 技術棧

- Flutter 3.x + Riverpod
- FastAPI + Pop2Piano + Basic Pitch
- Web Audio API + Tone.js（Salamander Grand Piano）
- OpenSheetMusicDisplay（MusicXML 樂譜渲染）

---

## 快速開始（一鍵啟動）

### 前置需求

| 工具 | 版本 | 安裝連結 |
|------|------|----------|
| Python | 3.12+ | https://python.org/downloads |
| Flutter | 3.x | https://docs.flutter.dev/get-started/install |
| Chrome | 最新 | 用於 Flutter Web 開發 |

### 一鍵啟動

```powershell
# 在 PowerShell 中執行（首次會自動安裝所有依賴）
.\dev.ps1
```

這會自動：
1. 建立 Python 虛擬環境並安裝依賴（含 PyTorch、Pop2Piano）
2. 安裝 Flutter 依賴
3. 啟動後端 API → http://localhost:8000/docs
4. 啟動前端 App → http://localhost:3000

### 其他指令

```powershell
.\dev.ps1 setup      # 只安裝依賴（不啟動）
.\dev.ps1 backend    # 只啟動後端
.\dev.ps1 frontend   # 只啟動前端
```

---

## 手動啟動（進階）

如果不想用一鍵腳本，可以手動操作：

### 後端

```powershell
cd noteflow_api
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
pip install torch transformers basic-pitch aiosqlite
uvicorn app.main:app --reload --port 8000
```

### 前端

```powershell
cd noteflow_app
flutter pub get
flutter run -d chrome --web-port 3000
```

---

## 開發須知

- 後端使用 SQLite（開發模式），不需要 PostgreSQL 或 Redis
- Pop2Piano 模型首次載入會下載 ~1.5GB（之後會快取）
- API 文件：http://localhost:8000/docs
- 前端 API 位址設定在 `noteflow_app/lib/core/constants/app_constants.dart`
