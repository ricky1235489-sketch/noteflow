"""Async transcription task via Celery."""
from pathlib import Path

from ..worker import celery_app
from ..config import settings


@celery_app.task(bind=True, name="transcribe_audio")
def transcribe_audio(self, transcription_id: str, audio_path: str):
    """Run transcription in background worker."""
    from ..services.transcription_service import TranscriptionService

    self.update_state(state="PROCESSING")

    try:
        service = TranscriptionService()
        result = service.transcribe(audio_path, transcription_id)

        return {
            "status": "completed",
            "midi_path": result.midi_path,
            "pdf_path": result.pdf_path,
            "duration_seconds": result.duration_seconds,
        }
    except Exception as exc:
        self.update_state(state="FAILED", meta={"error": str(exc)})
        raise
