"""Storage abstraction — local filesystem for MVP, S3/R2 for production."""
from __future__ import annotations

import uuid
from pathlib import Path
from typing import Optional

import boto3
from botocore.exceptions import ClientError

from ..config import settings


class StorageService:
    """Unified storage interface. Uses local FS when s3_bucket is empty."""

    def __init__(self):
        self._s3_client = None
        if settings.s3_bucket:
            self._s3_client = boto3.client(
                "s3",
                region_name=settings.s3_region,
                endpoint_url=settings.s3_endpoint_url or None,
                aws_access_key_id=settings.s3_access_key_id or None,
                aws_secret_access_key=settings.s3_secret_access_key or None,
            )

    @property
    def is_s3(self) -> bool:
        return self._s3_client is not None

    # ── Upload ────────────────────────────────────────────────

    def save_upload(self, content: bytes, filename: str) -> str:
        """Save uploaded file, return file_key."""
        suffix = Path(filename).suffix.lower()
        file_key = f"{uuid.uuid4()}{suffix}"

        if self.is_s3:
            self._s3_client.put_object(
                Bucket=settings.s3_bucket,
                Key=f"uploads/{file_key}",
                Body=content,
            )
        else:
            local_path = Path(settings.upload_dir) / file_key
            local_path.parent.mkdir(parents=True, exist_ok=True)
            local_path.write_bytes(content)

        return file_key

    def get_upload_path(self, file_key: str) -> str:
        """Get local path for an uploaded file (download from S3 if needed)."""
        local_path = Path(settings.upload_dir) / file_key

        if self.is_s3 and not local_path.exists():
            local_path.parent.mkdir(parents=True, exist_ok=True)
            self._s3_client.download_file(
                settings.s3_bucket, f"uploads/{file_key}", str(local_path)
            )

        return str(local_path)

    # ── Presigned URLs ────────────────────────────────────────

    def generate_presigned_upload_url(
        self, filename: str, expires_in: int = 3600
    ) -> dict:
        """Generate a presigned URL for direct client upload to S3.

        Returns {"upload_url": str, "file_key": str} if S3 is configured,
        otherwise returns empty upload_url (client should use POST /upload/audio).
        """
        suffix = Path(filename).suffix.lower()
        file_key = f"{uuid.uuid4()}{suffix}"

        if not self.is_s3:
            return {"upload_url": "", "file_key": file_key}

        content_type_map = {
            ".mp3": "audio/mpeg",
            ".wav": "audio/wav",
            ".m4a": "audio/mp4",
        }

        try:
            url = self._s3_client.generate_presigned_url(
                "put_object",
                Params={
                    "Bucket": settings.s3_bucket,
                    "Key": f"uploads/{file_key}",
                    "ContentType": content_type_map.get(suffix, "application/octet-stream"),
                },
                ExpiresIn=expires_in,
            )
            return {"upload_url": url, "file_key": file_key}
        except ClientError:
            return {"upload_url": "", "file_key": file_key}

    def generate_presigned_download_url(
        self, s3_key: str, expires_in: int = 3600
    ) -> Optional[str]:
        """Generate a presigned download URL for an S3 object."""
        if not self.is_s3:
            return None

        try:
            return self._s3_client.generate_presigned_url(
                "get_object",
                Params={"Bucket": settings.s3_bucket, "Key": s3_key},
                ExpiresIn=expires_in,
            )
        except ClientError:
            return None

    # ── Output files ──────────────────────────────────────────

    def save_output(self, local_path: str, transcription_id: str) -> str:
        """Upload output file to S3 if configured, return URL or local path."""
        if not self.is_s3:
            return local_path

        filename = Path(local_path).name
        s3_key = f"outputs/{transcription_id}/{filename}"
        self._s3_client.upload_file(local_path, settings.s3_bucket, s3_key)
        return s3_key


storage = StorageService()
