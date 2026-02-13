from datetime import datetime
from typing import Optional, Literal
from pydantic import BaseModel


class TranscriptionCreate(BaseModel):
    title: str
    audio_file_key: str
    composer: str | None = "composer4"  # Default: Balanced
    mode: Literal["auto", "pop2piano", "bytedance", "basic_pitch"] = "auto"
    """轉錄模式：
    - auto: 自動選擇（預設使用 pop2piano）
    - pop2piano: 流行音樂轉鋼琴編曲（適合非鋼琴音源）
    - bytedance: 高精度鋼琴轉錄（適合鋼琴錄音）
    - basic_pitch: 通用音高檢測
    """


class TranscriptionResponse(BaseModel):
    id: str
    title: str
    status: str  # "processing", "completed", "failed"
    original_audio_url: Optional[str] = None
    midi_url: Optional[str] = None
    pdf_url: Optional[str] = None
    musicxml_url: Optional[str] = None  # Added for OSMD rendering
    duration_seconds: Optional[float] = None
    created_at: datetime
    completed_at: Optional[datetime] = None
    # Progress tracking
    progress: int = 0  # 0-100 percentage
    progress_message: Optional[str] = None  # e.g., "載入模型中...", "轉換 MIDI..."
    # Error info
    error: Optional[str] = None

    model_config = {"from_attributes": True}


class UploadResponse(BaseModel):
    file_key: str
    filename: str
