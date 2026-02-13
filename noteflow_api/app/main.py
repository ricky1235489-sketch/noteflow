from contextlib import asynccontextmanager
import logging
import sys

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .config import settings
from .api.v1.router import api_router
from .core.exceptions import NoteFlowError
from .database import engine, Base


# 配置日誌
def setup_logging():
    """配置應用日誌"""
    log_format = "%(asctime)s | %(levelname)-8s | %(name)s:%(funcName)s:%(lineno)d | %(message)s"
    
    # 創建 handler
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(log_format))
    
    # 配置 root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.addHandler(handler)
    
    # 配置特定 logger
    logging.getLogger("noteflow").setLevel(logging.DEBUG)
    logging.getLogger("uvicorn").setLevel(logging.INFO)
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
    logging.getLogger("transformers").setLevel(logging.WARNING)
    logging.getLogger("librosa").setLevel(logging.WARNING)


setup_logging()
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create tables on startup (dev mode). Use Alembic migrations in prod."""
    logger.info("Starting NoteFlow API...")
    
    # Import models so they register with Base.metadata
    from . import models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    logger.info("Database initialized")

    # Preload Pop2Piano model in background to avoid cold-start delay
    # First request would otherwise wait 30-60s for model download/load
    import asyncio
    asyncio.create_task(_preload_model())

    yield
    
    logger.info("Shutting down NoteFlow API...")
    await engine.dispose()


async def _preload_model():
    """Preload the Pop2Piano model in background on startup."""
    import asyncio
    try:
        logger.info("Preloading Pop2Piano model in background...")
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _load_pop2piano_model)
        logger.info("Pop2Piano model preloaded successfully")
    except Exception as e:
        logger.warning(f"Model preload failed (will load on first request): {e}")


def _load_pop2piano_model():
    """Synchronous model loading for executor."""
    try:
        from transformers import Pop2PianoForConditionalGeneration
        import torch

        # Use the same fallback loader as AudioProcessor
        from .services.audio_processor import _load_pop2piano_processor
        processor = _load_pop2piano_processor("sweetcocoa/pop2piano")
        model = Pop2PianoForConditionalGeneration.from_pretrained("sweetcocoa/pop2piano")

        if torch.cuda.is_available():
            model = model.cuda()
        model.eval()

        # Store in module-level cache for AudioProcessor to pick up
        from .services import audio_processor as ap_module
        ap_module._preloaded_model = model
        ap_module._preloaded_processor = processor
    except Exception as e:
        logger.warning(f"Pop2Piano preload error: {e}")


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        docs_url="/docs",
        redoc_url="/redoc",
        lifespan=lifespan,
    )

    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Dev mode: allow all
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Global error handler
    @app.exception_handler(Exception)
    async def global_error_handler(request: Request, exc: Exception):
        logger.exception(f"Unhandled error: {exc}")
        return JSONResponse(
            status_code=500,
            content={
                "success": False, 
                "error": "內部伺服器錯誤",
                "detail": str(exc) if settings.debug else None
            },
        )

    # NoteFlow error handler
    @app.exception_handler(NoteFlowError)
    async def noteflow_error_handler(request: Request, exc: NoteFlowError):
        return JSONResponse(
            status_code=exc.status_code,
            content={"success": False, "error": exc.message},
        )

    # Routes
    app.include_router(api_router)

    @app.get("/health")
    async def health_check():
        import torch
        import librosa
        
        return {
            "status": "ok",
            "app": settings.app_name,
            "gpu_available": torch.cuda.is_available(),
            "librosa_version": librosa.__version__,
        }

    return app


app = create_app()
