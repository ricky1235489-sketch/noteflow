from __future__ import annotations

import logging
from pathlib import Path
from typing import Callable, Optional

from ..config import settings
from ..core.exceptions import FileValidationError, TranscriptionFailed

logger = logging.getLogger(__name__)


class TranscriptionResult:
    def __init__(
        self,
        midi_path: str,
        musicxml_path: str,
        pdf_path: str | None,
        duration_seconds: float,
    ):
        self.midi_path = midi_path
        self.musicxml_path = musicxml_path
        self.pdf_path = pdf_path
        self.duration_seconds = duration_seconds


class TranscriptionService:
    """音訊轉譜核心服務"""

    def __init__(self, progress_callback: Optional[Callable[[int, str], None]] = None):
        """初始化音訊處理器

        Args:
            progress_callback: 進度回調函數，接收 (progress: int, message: str)
        """
        from .audio_processor import AudioProcessor
        from .midi_converter import MidiConverter
        from .sheet_generator import SheetGenerator

        self.audio_processor = AudioProcessor(progress_callback=progress_callback)
        self.midi_converter = MidiConverter()
        self.sheet_generator = SheetGenerator()
        self._progress_callback = progress_callback

    def transcribe(self, audio_path: str, transcription_id: str, mode: str = "auto", composer: str = "composer4") -> TranscriptionResult:
        self._validate_file(audio_path)

        output_dir = Path(settings.output_dir) / transcription_id
        output_dir.mkdir(parents=True, exist_ok=True)

        logger.info(f"Starting transcription: {audio_path}")

        def _report(progress: int, message: str):
            """Report progress"""
            if self._progress_callback:
                self._progress_callback(progress, message)
            logger.info(f"Progress {progress}%: {message}")

        try:
            # 0-10%: 準備階段
            _report(5, "準備轉譜環境...")

            # 10-15%: 取得音訊長度
            duration = self.audio_processor.get_duration(audio_path)
            logger.info(f"Audio duration: {duration:.1f}s")

            # 15-80%: 音訊 → MIDI (最耗時的步驟)
            _report(15, f"分析音訊中... (歌曲長度: {int(duration)}秒)")
            logger.info(f"Transcribing with mode={mode}, composer={composer}")
            raw_midi = self.audio_processor.audio_to_midi(audio_path, mode=mode, composer=composer)
            logger.info(f"MIDI generated with {sum(len(inst.notes) for inst in raw_midi.instruments)} notes")

            # 80-85%: 量化 MIDI
            _report(80, "優化節奏與速度...")
            quantized_midi = self.midi_converter.quantize_midi(raw_midi, grid="16th")
            logger.info(f"Quantized MIDI to 16th note grid")

            # 85-90%: 處理左手編排
            has_bass_notes = any(
                note.pitch < 60 
                for inst in quantized_midi.instruments 
                for note in inst.notes
            )
            
            if has_bass_notes:
                final_midi = quantized_midi
                logger.info("Using Pop2Piano output directly (has bass notes)")
            else:
                _report(85, "編排左手鋼琴分部...")
                final_midi = self.midi_converter.create_two_hand_midi(quantized_midi)
                logger.info("Added left hand arrangement")

            # 90-95%: 儲存 MIDI 和生成 MusicXML
            _report(90, "產生樂譜檔案...")
            midi_path = str(output_dir / "sheet.mid")
            final_midi.write(midi_path)
            logger.info(f"MIDI saved: {midi_path}")

            # 95-100%: 生成 MusicXML
            musicxml_path = str(output_dir / "sheet.musicxml")
            try:
                self.sheet_generator.midi_to_musicxml(midi_path, musicxml_path)
                logger.info(f"MusicXML generated: {musicxml_path}")
            except Exception as e:
                logger.warning(f"MusicXML generation failed: {e}")
                musicxml_path = None

            # 7. 嘗試產生 PDF
            pdf_path = str(output_dir / "sheet.pdf")
            try:
                self.sheet_generator.midi_to_pdf(midi_path, pdf_path)
                logger.info(f"PDF generated: {pdf_path}")
            except Exception as e:
                logger.warning(f"PDF generation failed: {e}")
                pdf_path = None

            logger.info(f"Transcription completed: {transcription_id}")
            return TranscriptionResult(
                midi_path=midi_path,
                musicxml_path=musicxml_path,
                pdf_path=pdf_path,
                duration_seconds=duration,
            )

        except Exception as exc:
            logger.exception(f"Transcription failed: {exc}")
            raise TranscriptionFailed(f"轉譜處理失敗: {exc}") from exc

    def _validate_file(self, audio_path: str) -> None:
        path = Path(audio_path)

        if not path.exists():
            raise FileValidationError(f"檔案不存在: {audio_path}")

        suffix = path.suffix.lower()
        if suffix not in settings.allowed_extensions:
            raise FileValidationError(f"不支援的檔案格式: {suffix}")

        file_size = path.stat().st_size
        if file_size > settings.max_file_size_bytes:
            raise FileValidationError(
                f"檔案過大: {file_size / 1024 / 1024:.1f}MB (上限 50MB)"
            )
