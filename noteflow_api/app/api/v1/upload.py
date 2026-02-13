"""File upload endpoints — local storage for MVP, S3 presigned URLs for prod."""
from pathlib import Path

from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel

from ...config import settings
from ...schemas.common import ApiResponse
from ...schemas.transcription import UploadResponse
from ...core.storage import storage

router = APIRouter(prefix="/upload", tags=["upload"])


class PresignedUrlRequest(BaseModel):
    filename: str


class PresignedUrlResponse(BaseModel):
    upload_url: str
    file_key: str


@router.post("/audio", response_model=ApiResponse[UploadResponse])
async def upload_audio(file: UploadFile = File(...)):
    """上傳音訊檔案（直接上傳至後端）"""
    if file.filename is None:
        raise HTTPException(status_code=400, detail="缺少檔案名稱")

    suffix = Path(file.filename).suffix.lower()
    if suffix not in settings.allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"不支援的檔案格式: {suffix}。支援: {', '.join(settings.allowed_extensions)}",
        )

    content = await file.read()

    if len(content) > settings.max_file_size_bytes:
        raise HTTPException(status_code=400, detail="檔案過大 (上限 50MB)")

    file_key = storage.save_upload(content, file.filename)

    return ApiResponse(
        success=True,
        data=UploadResponse(file_key=file_key, filename=file.filename),
    )


@router.post("/presigned-url", response_model=ApiResponse[PresignedUrlResponse])
async def get_presigned_upload_url(body: PresignedUrlRequest):
    """取得 S3 presigned upload URL（生產環境用）。

    若未設定 S3，upload_url 為空字串，客戶端應改用 POST /upload/audio。
    """
    suffix = Path(body.filename).suffix.lower()
    if suffix not in settings.allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"不支援的檔案格式: {suffix}",
        )

    result = storage.generate_presigned_upload_url(body.filename)

    return ApiResponse(
        success=True,
        data=PresignedUrlResponse(**result),
    )
