"""Transcription CRUD endpoints with rate limiting."""
import uuid
import asyncio
from datetime import datetime, timezone
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from ...config import settings
from ...core.auth import get_current_user, get_optional_user
from ...core.rate_limiter import RateLimiter
from ...core.storage import storage
from ...database import get_db
from ...models.transcription import Transcription
from ...models.user import User
from ...schemas.common import ApiResponse
from ...schemas.transcription import TranscriptionCreate, TranscriptionResponse
from ...services.transcription_service import TranscriptionService

router = APIRouter(prefix="/transcriptions", tags=["transcriptions"])

# In-memory store for MVP (replace with DB later)
_transcriptions: dict[str, dict] = {}

# Thread pool for background processing
_executor = ThreadPoolExecutor(max_workers=1)


async def run_transcription_sync(
    transcription_id: str,
    audio_path: str,
    composer: str,
    max_duration: float,
):
    """Simple synchronous transcription runner"""
    import os
    
    # Get absolute path
    audio_path = str(Path(audio_path).resolve())
    
    # Change to app directory
    app_dir = Path(__file__).parent.parent.parent
    os.chdir(str(app_dir))
    
    print(f"[SYNC] Audio: {audio_path}")
    print(f"[SYNC] Exists: {os.path.exists(audio_path)}")
    
    try:
        from app.services.transcription_service import TranscriptionService
        service = TranscriptionService()
        result = service.transcribe(audio_path, transcription_id, composer=composer)
        
        print(f"[SYNC] Success: {result.midi_path}")
        return result
    except Exception as e:
        print(f"[SYNC] Error: {e}")
        import traceback
        traceback.print_exc()
        raise


async def _save_transcription_to_db(
    db: AsyncSession,
    transcription_id: str,
    title: str,
    status: str = "pending",
    progress: int = 0,
    progress_message: str = "準備中...",
    original_audio_url: str = None,
    midi_url: str = None,
    pdf_url: str = None,
    musicxml_url: str = None,
    duration_seconds: float = None,
    error: str = None,
    user_id: str = "guest",
):
    """Save or update transcription record in SQLite database."""
    try:
        from ...models.transcription import Transcription
        from sqlalchemy import text

        # Check if exists
        result = await db.execute(
            text("SELECT id FROM transcriptions WHERE id = :id"),
            {"id": transcription_id}
        )
        existing = result.fetchone()

        if existing:
            # Update existing
            await db.execute(
                text("""
                    UPDATE transcriptions SET
                        status = :status,
                        progress = :progress,
                        progress_message = :progress_message,
                        midi_url = :midi_url,
                        pdf_url = :pdf_url,
                        musicxml_url = :musicxml_url,
                        duration_seconds = :duration_seconds,
                        completed_at = :completed_at,
                        error = :error
                    WHERE id = :id
                """),
                {
                    "id": transcription_id,
                    "status": status,
                    "progress": progress,
                    "progress_message": progress_message,
                    "midi_url": midi_url,
                    "pdf_url": pdf_url,
                    "musicxml_url": musicxml_url,
                    "duration_seconds": duration_seconds,
                    "completed_at": datetime.now(timezone.utc) if status == "completed" else None,
                    "error": error,
                }
            )
        else:
            # Insert new
            await db.execute(
                text("""
                    INSERT INTO transcriptions
                    (id, user_id, title, status, progress, progress_message,
                     original_audio_url, midi_url, pdf_url, musicxml_url,
                     duration_seconds, created_at, completed_at, error)
                    VALUES
                    (:id, :user_id, :title, :status, :progress, :progress_message,
                     :original_audio_url, :midi_url, :pdf_url, :musicxml_url,
                     :duration_seconds, :created_at, :completed_at, :error)
                """),
                {
                    "id": transcription_id,
                    "user_id": user_id,
                    "title": title,
                    "status": status,
                    "progress": progress,
                    "progress_message": progress_message,
                    "original_audio_url": original_audio_url,
                    "midi_url": midi_url,
                    "pdf_url": pdf_url,
                    "musicxml_url": musicxml_url,
                    "duration_seconds": duration_seconds,
                    "created_at": datetime.now(timezone.utc),
                    "completed_at": None,
                    "error": error,
                }
            )
        await db.commit()
    except Exception as e:
        print(f"Error saving to DB: {e}")


async def _get_transcription_from_db(db: AsyncSession, transcription_id: str) -> dict | None:
    """Get transcription from database."""
    try:
        from ...models.transcription import Transcription
        from sqlalchemy import text

        result = await db.execute(
            text("""
                SELECT id, user_id, title, status, progress, progress_message,
                       original_audio_url, midi_url, pdf_url, musicxml_url,
                       duration_seconds, created_at, completed_at, error
                FROM transcriptions WHERE id = :id
            """),
            {"id": transcription_id}
        )
        row = result.fetchone()
        if row:
            # Map columns by position (must match SELECT order)
            return {
                "id": row[0],
                "user_id": row[1],
                "title": row[2],
                "status": row[3],
                "progress": row[4],
                "progress_message": row[5],
                "original_audio_url": row[6],
                "midi_url": row[7],
                "pdf_url": row[8],
                "musicxml_url": row[9],
                "duration_seconds": row[10],
                "created_at": row[11],
                "completed_at": row[12],
                "error": row[13],
            }
    except Exception as e:
        print(f"Error reading from DB: {e}")
        import traceback
        traceback.print_exc()
    return None


async def run_transcription_task(transcription_id: str, audio_path: str, composer: str = "composer4"):
    """Run transcription in a thread pool to avoid blocking the event loop."""
    loop = asyncio.get_event_loop()
    service = TranscriptionService()
    
    try:
        result = await loop.run_in_executor(
            _executor,
            lambda: service.transcribe(audio_path, transcription_id, composer=composer)
        )
        
        # Update record
        record = _transcriptions.get(transcription_id)
        if record:
            record["status"] = "completed"
            record["midi_url"] = result.midi_path
            record["pdf_url"] = result.pdf_path
            record["duration_seconds"] = result.duration_seconds
            record["completed_at"] = datetime.now(timezone.utc)
            
        print(f"[OK] Transcription completed: {transcription_id}")
        return result
        
    except Exception as exc:
        record = _transcriptions.get(transcription_id)
        if record:
            record["status"] = "failed"
        print(f"[FAIL] Transcription failed: {transcription_id} - {exc}")
        import traceback
        traceback.print_exc()
        raise


@router.post("", response_model=ApiResponse[TranscriptionResponse])
async def create_transcription(
    body: TranscriptionCreate,
    user: User | None = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
    background_tasks: BackgroundTasks = None,
):
    """建立轉譜任務"""
    
    # Rate limit check for authenticated users
    if user is not None:
        await RateLimiter.check_and_increment(user, db)

    transcription_id = str(uuid.uuid4())
    audio_path = storage.get_upload_path(body.audio_file_key)
    
    # Ensure absolute path
    audio_path = str(Path(audio_path).resolve())
    print(f"[DEBUG] Audio path: {audio_path}")
    print(f"[DEBUG] Audio exists: {Path(audio_path).exists()}")

    if not Path(audio_path).exists():
        raise HTTPException(status_code=404, detail="找不到音訊檔案")

    # Check duration limit (we'll verify after transcription completes)
    if user is not None:
        max_duration = RateLimiter.get_max_duration(user)
    else:
        max_duration = settings.pro_max_duration_seconds  # Guest mode

    # Check file duration early if possible
    try:
        from ...services.audio_processor import AudioProcessor
        processor = AudioProcessor()
        file_duration = processor.get_duration(audio_path)
        if file_duration > max_duration:
            raise HTTPException(
                status_code=400,
                detail=f"音訊長度 {file_duration:.0f}s 超過上限 {max_duration}s"
            )
    except Exception as e:
        print(f"Could not pre-check duration: {e}")

    record = {
        "id": transcription_id,
        "title": body.title,
        "status": "processing",
        "original_audio_url": audio_path,
        "midi_url": None,
        "pdf_url": None,
        "duration_seconds": None,
        "created_at": datetime.now(timezone.utc),
        "completed_at": None,
        "progress": 0,
        "progress_message": "準備中...",
    }
    _transcriptions[transcription_id] = record

    # Also save to SQLite database for persistence
    user_id = str(user.id) if user else "guest"
    await _save_transcription_to_db(
        db=db,
        transcription_id=transcription_id,
        title=body.title,
        status="processing",
        progress=0,
        progress_message="開始轉譜...",
        original_audio_url=audio_path,
        user_id=user_id,
    )

    # Run transcription SYNCHRONOUSLY (blocking but reliable)
    # This is a simple inline implementation to avoid any function call issues
    try:
        import os
        
        # Debug: write to file
        debug_log = Path("debug.log")
        debug_log.write_text(f"Starting at {datetime.now()}\n")
        
        # Ensure absolute path
        audio_path_new = str(Path(audio_path).resolve())
        app_dir = Path(__file__).parent.parent.parent
        os.chdir(str(app_dir))
        
        debug_log.write_text(f"Audio: {audio_path_new}, Exists: {os.path.exists(audio_path_new)}\n")
        
        # Import and run directly
        from app.services.transcription_service import TranscriptionService
        service = TranscriptionService()
        
        debug_log.write_text("Calling transcribe...\n")
        
        # Use the resolved absolute path
        result = service.transcribe(audio_path_new, transcription_id, composer=body.composer or "composer4")

        debug_log.write_text(f"Done: {result.midi_path}\n")
        
        # Update success
        record["status"] = "completed"
        record["midi_url"] = result.midi_path
        record["pdf_url"] = result.pdf_path
        record["musicxml_url"] = result.musicxml_path
        record["duration_seconds"] = result.duration_seconds
        record["completed_at"] = datetime.now(timezone.utc)
        record["progress"] = 100
        record["progress_message"] = "完成！"
        
        # Save to database
        await _save_transcription_to_db(
            db=db,
            transcription_id=transcription_id,
            title=body.title,
            status="completed",
            progress=100,
            progress_message="完成！",
            midi_url=result.midi_path,
            pdf_url=result.pdf_path,
            musicxml_url=result.musicxml_path,
            duration_seconds=result.duration_seconds,
            user_id=user_id,
        )
        
        # Get the URLs for response
        midi_url = f"/api/v1/transcriptions/{transcription_id}/download?type=midi"
        musicxml_url = f"/api/v1/transcriptions/{transcription_id}/download?type=musicxml"
        
    except Exception as e:
        import traceback
        error_msg = f"{e}"
        print(f"[SYNC_API_ERROR] {error_msg}")
        traceback.print_exc()
        
        record["status"] = "failed"
        record["error"] = error_msg
        record["progress_message"] = "轉譜失敗"
        
        await _save_transcription_to_db(
            db=db,
            transcription_id=transcription_id,
            title=body.title,
            status="failed",
            progress=0,
            progress_message="轉譜失敗",
            error=error_msg,
            user_id=user_id,
        )

    return ApiResponse(
        success=True,
        data=TranscriptionResponse(**record),
    )


async def _run_transcription_background(
    transcription_id: str,
    audio_path: str,
    composer: str,
    max_duration: float,
):
    """Background task that runs transcription without blocking the API."""
    try:
        record = _transcriptions.get(transcription_id)
        if not record:
            return

        # 初始化進度
        record["progress"] = 5
        record["progress_message"] = "準備轉譜環境..."

        # 創建進度回調函數，定期更新資料庫
        async def progress_callback(progress: int, message: str):
            """更新進度到記憶體和資料庫"""
            record["progress"] = progress
            record["progress_message"] = message

            # 每 10% 或重要訊息時更新資料庫
            if progress % 10 == 0 or progress >= 80:
                try:
                    from ...database import async_session_factory
                    async with async_session_factory() as db:
                        await _save_transcription_to_db(
                            db=db,
                            transcription_id=transcription_id,
                            title=record["title"],
                            status="processing",
                            progress=progress,
                            progress_message=message,
                        )
                except Exception as e:
                    print(f"Error updating progress to DB: {e}")

        # 更新初始狀態到資料庫
        try:
            from ...database import async_session_factory
            async with async_session_factory() as db:
                await _save_transcription_to_db(
                    db=db,
                    transcription_id=transcription_id,
                    title=record["title"],
                    status="processing",
                    progress=5,
                    progress_message="準備轉譜環境...",
                )
        except Exception as e:
            print(f"Error saving initial status to DB: {e}")

        # Run transcription using new sync method
        try:
            print(f"[API] About to run transcription: {transcription_id}")
            result = await run_transcription_sync(
                transcription_id,
                audio_path,
                composer,
                max_duration
            )
            print(f"[API] Transcription completed: {result}")
        except Exception as transcribe_error:
            import traceback
            error_details = traceback.format_exc()
            print(f"[TRANSCRIPTION ERROR] {transcribe_error}")
            print(f"[TRACE] {error_details}")
            record["status"] = "failed"
            record["error"] = f"{transcribe_error}"
            record["progress_message"] = "轉譜失敗"
            try:
                from ...database import async_session_factory
                async with async_session_factory() as db:
                    await _save_transcription_to_db(
                        db=db,
                        transcription_id=transcription_id,
                        title=record["title"],
                        status="failed",
                        progress=0,
                        progress_message="轉譜失敗",
                        error=str(transcribe_error),
                    )
            except Exception as db_error:
                print(f"Error saving failure to DB: {db_error}")
            return

        # Check duration limit
        if result.duration_seconds and result.duration_seconds > max_duration:
            record["status"] = "failed"
            record["progress_message"] = f"超過長度限制 {max_duration}s"
            record["error"] = f"音訊長度 {result.duration_seconds:.0f}s 超過上限 {max_duration}s"
            # 更新資料庫
            try:
                from ...database import async_session_factory
                async with async_session_factory() as db:
                    await _save_transcription_to_db(
                        db=db,
                        transcription_id=transcription_id,
                        title=record["title"],
                        status="failed",
                        progress=0,
                        progress_message=f"超過長度限制 {max_duration}s",
                        error=f"音訊長度 {result.duration_seconds:.0f}s 超過上限 {max_duration}s",
                    )
            except Exception as e:
                print(f"Error saving failure to DB: {e}")
            return

        # Update successful result
        record["status"] = "completed"
        record["midi_url"] = result.midi_path
        record["pdf_url"] = result.pdf_path
        record["musicxml_url"] = result.musicxml_path
        record["duration_seconds"] = result.duration_seconds
        record["completed_at"] = datetime.now(timezone.utc)
        record["progress"] = 100
        record["progress_message"] = "完成！"

        # Save to SQLite database for persistence
        from sqlalchemy.ext.asyncio import AsyncSession
        from ...database import async_session_factory

        try:
            async with async_session_factory() as db:
                await _save_transcription_to_db(
                    db=db,
                    transcription_id=transcription_id,
                    title=record["title"],
                    status="completed",
                    progress=100,
                    progress_message="完成！",
                    midi_url=result.midi_path,
                    pdf_url=result.pdf_path,
                    musicxml_url=result.musicxml_path,
                    duration_seconds=result.duration_seconds,
                )
        except Exception as e:
            print(f"Error saving completion to DB: {e}")

        print(f"[OK] Transcription completed: {transcription_id}")

    except HTTPException as he:
        record = _transcriptions.get(transcription_id)
        if record:
            record["status"] = "failed"
            record["error"] = he.detail
            record["progress_message"] = "處理失敗"
    except Exception as exc:
        record = _transcriptions.get(transcription_id)
        if record:
            record["status"] = "failed"
            record["error"] = str(exc)
            record["progress_message"] = "處理失敗"
        print(f"[FAIL] Transcription failed: {transcription_id} - {exc}")
        import traceback
        traceback.print_exc()


@router.get("", response_model=ApiResponse[list[TranscriptionResponse]])
async def list_transcriptions(db: AsyncSession = Depends(get_db)):
    """列出所有轉譜記錄"""
    # First check in-memory store
    items = [
        TranscriptionResponse(**t)
        for t in sorted(
            _transcriptions.values(),
            key=lambda x: x["created_at"],
            reverse=True,
        )
    ]

    # Also try to load from database for persistence
    try:
        from sqlalchemy import text
        result = await db.execute(
            text("""
                SELECT id, user_id, title, status, progress, progress_message,
                       original_audio_url, midi_url, pdf_url, musicxml_url,
                       duration_seconds, created_at, completed_at, error
                FROM transcriptions ORDER BY created_at DESC
            """)
        )
        rows = result.fetchall()

        # Merge DB records with in-memory (DB has priority for persistence)
        db_items = []
        for row in rows:
            item = {
                "id": row[0],
                "user_id": row[1],
                "title": row[2],
                "status": row[3],
                "progress": row[4],
                "progress_message": row[5],
                "original_audio_url": row[6],
                "midi_url": row[7],
                "pdf_url": row[8],
                "musicxml_url": row[9],
                "duration_seconds": row[10],
                "created_at": row[11],
                "completed_at": row[12],
                "error": row[13],
            }
            # Only add if not already in memory (DB is source of truth)
            if item["id"] not in _transcriptions:
                db_items.append(TranscriptionResponse(**item))

        items = db_items + items
    except Exception as e:
        print(f"Error loading from DB: {e}")

    return ApiResponse(success=True, data=items)


@router.get("/{transcription_id}", response_model=ApiResponse[TranscriptionResponse])
async def get_transcription(transcription_id: str, db: AsyncSession = Depends(get_db)):
    """取得單一轉譜結果"""
    # First check in-memory store
    record = _transcriptions.get(transcription_id)

    # If not in memory, try database
    if record is None:
        record = await _get_transcription_from_db(db, transcription_id)

    if record is None:
        raise HTTPException(status_code=404, detail="找不到轉譜記錄")

    return ApiResponse(success=True, data=TranscriptionResponse(**record))


@router.get("/{transcription_id}/status")
async def get_transcription_status(transcription_id: str):
    """取得轉譜進度（輪詢用）"""
    record = _transcriptions.get(transcription_id)
    if record is None:
        raise HTTPException(status_code=404, detail="找不到轉譜記錄")

    return {
        "id": transcription_id,
        "status": record.get("status", "unknown"),
        "progress": record.get("progress", 0),
        "progress_message": record.get("progress_message", ""),
        "error": record.get("error"),
        "completed_at": record.get("completed_at"),
    }


@router.get("/{transcription_id}/midi")
async def export_midi(transcription_id: str, db: AsyncSession = Depends(get_db)):
    """匯出 MIDI 檔案"""
    # First check in-memory store
    record = _transcriptions.get(transcription_id)

    # If not in memory, try database
    if record is None:
        record = await _get_transcription_from_db(db, transcription_id)

    if record is None:
        raise HTTPException(status_code=404, detail="找不到轉譜記錄")

    # 檢查轉譜狀態
    status = record.get("status", "")
    if status != "completed":
        raise HTTPException(
            status_code=202,  # Accepted - Processing
            detail={
                "message": "轉譜處理中，請稍候...",
                "status": status,
                "progress": record.get("progress", 0),
                "progress_message": record.get("progress_message", "")
            }
        )

    midi_path = record.get("midi_url")
    if midi_path is None or not Path(midi_path).exists():
        raise HTTPException(status_code=404, detail="MIDI 檔案不存在")

    return FileResponse(
        midi_path,
        media_type="audio/midi",
        filename=f"{record['title']}.mid",
    )


@router.get("/{transcription_id}/pdf")
async def export_pdf(transcription_id: str, db: AsyncSession = Depends(get_db)):
    """匯出 PDF 樂譜"""
    # First check in-memory store
    record = _transcriptions.get(transcription_id)

    # If not in memory, try database
    if record is None:
        record = await _get_transcription_from_db(db, transcription_id)

    if record is None:
        raise HTTPException(status_code=404, detail="找不到轉譜記錄")

    # 檢查轉譜狀態
    status = record.get("status", "")
    if status != "completed":
        raise HTTPException(
            status_code=202,  # Accepted - Processing
            detail={
                "message": "轉譜處理中，請稍候...",
                "status": status,
                "progress": record.get("progress", 0),
                "progress_message": record.get("progress_message", "")
            }
        )

    pdf_path = record.get("pdf_url")
    if pdf_path is None or not Path(pdf_path).exists():
        raise HTTPException(status_code=404, detail="PDF 檔案不存在")

    return FileResponse(
        pdf_path,
        media_type="application/pdf",
        filename=f"{record['title']}.pdf",
    )


@router.get("/{transcription_id}/musicxml")
async def export_musicxml(transcription_id: str, db: AsyncSession = Depends(get_db)):
    """匯出 MusicXML 樂譜（用於 OSMD 渲染）"""
    from fastapi.responses import Response

    # Check in-memory store first
    record = _transcriptions.get(transcription_id)

    # If not in memory, try database
    if record is None:
        record = await _get_transcription_from_db(db, transcription_id)

    if record is None:
        raise HTTPException(status_code=404, detail="找不到轉譜記錄")

    # 檢查轉譜狀態
    status = record.get("status", "")
    if status != "completed":
        raise HTTPException(
            status_code=202,  # Accepted - Processing
            detail={
                "message": "轉譜處理中，請稍候...",
                "status": status,
                "progress": record.get("progress", 0),
                "progress_message": record.get("progress_message", "")
            }
        )

    # MusicXML 檔案路徑（與 MIDI 同目錄）
    midi_path = record.get("midi_url")
    if midi_path is None:
        raise HTTPException(status_code=404, detail="轉譜尚未完成")

    musicxml_path = Path(midi_path).parent / "sheet.musicxml"
    print(f"[MusicXML] Looking for: {musicxml_path} (exists: {musicxml_path.exists()})")

    if not musicxml_path.exists():
        # 嘗試即時產生 MusicXML
        print(f"[MusicXML] File not found, generating on-the-fly...")
        try:
            from ...services.sheet_generator import SheetGenerator
            generator = SheetGenerator()
            generator.midi_to_musicxml(str(midi_path), str(musicxml_path))
            print(f"[MusicXML] Generated successfully: {musicxml_path}")
        except Exception as e:
            print(f"[MusicXML] Generation failed: {e}")
            import traceback
            traceback.print_exc()
            raise HTTPException(status_code=500, detail=f"MusicXML 生成失敗: {e}")

    # 讀取並返回 XML 內容
    xml_content = musicxml_path.read_text(encoding="utf-8")
    
    return Response(
        content=xml_content,
        media_type="application/vnd.recordare.musicxml+xml",
    )


# ========== 刪除相關端點 ==========
# 注意：特殊路由 (/, /selected) 必須在動態路由 {transcription_id} 之前定義

@router.delete("/selected")
async def delete_selected_transcriptions(
    transcription_ids: list[str],
    db: AsyncSession = Depends(get_db),
):
    """刪除選定的轉譜記錄"""
    if not transcription_ids:
        raise HTTPException(status_code=400, detail="沒有選擇要刪除的項目")

    deleted_count = 0
    deleted_files = []
    errors = []

    for transcription_id in transcription_ids:
        try:
            record = await _get_transcription_from_db(db, transcription_id)
            if record:
                # 刪除相關檔案
                for key in ['original_audio_url', 'midi_url', 'pdf_url', 'musicxml_url']:
                    path = record.get(key)
                    if path:
                        file_path = Path(path)
                        if file_path.exists():
                            try:
                                file_path.unlink()
                                deleted_files.append(str(file_path))
                            except Exception as e:
                                errors.append({"file": path, "error": str(e)})

                # 從資料庫刪除記錄
                await db.execute(
                    text('DELETE FROM transcriptions WHERE id = :id'),
                    {"id": transcription_id}
                )
                deleted_count += 1
        except Exception as e:
            errors.append({"id": transcription_id, "error": str(e)})

    await db.commit()

    return ApiResponse(
        success=True,
        data={
            "deleted_count": deleted_count,
            "deleted_files_count": len(deleted_files),
            "errors": errors
        },
        error=None
    )


@router.delete("/")
async def delete_all_transcriptions(
    db: AsyncSession = Depends(get_db),
):
    """刪除所有轉譜記錄及相關檔案"""
    try:
        # 獲取所有記錄
        result = await db.execute(text('SELECT id FROM transcriptions'))
        records = result.fetchall()

        deleted_count = 0
        deleted_files = []

        for (transcription_id,) in records:
            # 獲取記錄的檔案路徑
            record = await _get_transcription_from_db(db, transcription_id)
            if record:
                # 刪除相關檔案
                for key in ['original_audio_url', 'midi_url', 'pdf_url', 'musicxml_url']:
                    path = record.get(key)
                    if path:
                        file_path = Path(path)
                        if file_path.exists():
                            try:
                                file_path.unlink()
                                deleted_files.append(str(file_path))
                            except:
                                pass

        # 刪除所有記錄
        await db.execute(text('DELETE FROM transcriptions'))
        await db.commit()

        deleted_count = len(records)

        return ApiResponse(
            success=True,
            data={
                "deleted_count": deleted_count,
                "deleted_files_count": len(deleted_files)
            },
            error=None
        )
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"刪除失敗: {str(e)}")


@router.delete("/{transcription_id}")
async def delete_transcription(
    transcription_id: str,
    db: AsyncSession = Depends(get_db),
):
    """刪除單個轉譜記錄及相關檔案"""
    # 從資料庫獲取記錄
    record = await _get_transcription_from_db(db, transcription_id)
    if record is None:
        raise HTTPException(status_code=404, detail="找不到轉譜記錄")
    
    try:
        # 刪除相關檔案
        file_paths = []
        for key in ['original_audio_url', 'midi_url', 'pdf_url', 'musicxml_url']:
            path = record.get(key)
            if path:
                file_path = Path(path)
                if file_path.exists():
                    file_path.unlink()
                    file_paths.append(str(file_path))
        
        # 從資料庫刪除記錄
        await db.execute(
            text('DELETE FROM transcriptions WHERE id = :id'),
            {"id": transcription_id}
        )
        await db.commit()
        
        return ApiResponse(
            success=True,
            data={"deleted_files": file_paths},
            error=None
        )
    except Exception as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail=f"刪除失敗: {str(e)}")
