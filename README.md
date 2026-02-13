# NoteFlow

將音樂檔案轉換為鋼琴樂譜的跨平台應用程式。

## 專案結構

- `noteflow_app/` — Flutter 前端（Web / Mobile）
- `noteflow_api/` — FastAPI 後端（音訊處理 + 轉譜引擎）
- `docs/` — 產品需求、架構設計、技術文件

## 技術棧

- Flutter 3.x + Riverpod
- FastAPI + Basic Pitch (Spotify) + TensorFlow
- Web Audio API（鋼琴音色合成）

## 快速開始

### 後端
```bash
cd noteflow_api
python -m venv .venv312
.venv312\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

### 前端
```bash
cd noteflow_app
flutter run -d chrome
```
