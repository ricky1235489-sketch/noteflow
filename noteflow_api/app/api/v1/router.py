from fastapi import APIRouter

from .auth import router as auth_router
from .upload import router as upload_router
from .transcriptions import router as transcriptions_router
from .users import router as users_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth_router)
api_router.include_router(upload_router)
api_router.include_router(transcriptions_router)
api_router.include_router(users_router)
