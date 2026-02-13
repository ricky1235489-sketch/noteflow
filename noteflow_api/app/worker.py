"""Celery worker for async transcription tasks."""
from celery import Celery

from .config import settings

celery_app = Celery(
    "noteflow",
    broker=settings.redis_url,
    backend=settings.redis_url,
)

celery_app.conf.update(
    task_serializer="json",
    accept_content=["json"],
    result_serializer="json",
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
    task_time_limit=600,  # 10 min max per task
    task_soft_time_limit=540,
)
