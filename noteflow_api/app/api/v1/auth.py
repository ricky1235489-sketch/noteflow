"""Authentication endpoints."""
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.auth import get_current_user, _decode_firebase_token
from ...database import get_db
from ...models.user import User
from ...schemas.common import ApiResponse

router = APIRouter(prefix="/auth", tags=["auth"])


class RegisterRequest(BaseModel):
    firebase_token: str
    display_name: str | None = None


class LoginRequest(BaseModel):
    firebase_token: str


class UserResponse(BaseModel):
    id: str
    email: str
    display_name: str | None
    is_pro: bool
    monthly_conversions_used: int

    model_config = {"from_attributes": True}


@router.post("/register", response_model=ApiResponse[UserResponse])
async def register(body: RegisterRequest, db: AsyncSession = Depends(get_db)):
    """Register a new user with Firebase token."""
    payload = _decode_firebase_token(body.firebase_token)
    firebase_uid = payload.get("sub") or payload.get("user_id")
    email = payload.get("email", "")

    if not firebase_uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Token 缺少使用者 ID",
        )

    # Check if user already exists
    result = await db.execute(
        select(User).where(User.firebase_uid == firebase_uid)
    )
    existing = result.scalar_one_or_none()
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="使用者已存在",
        )

    user = User(
        firebase_uid=firebase_uid,
        email=email,
        display_name=body.display_name or payload.get("name"),
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    return ApiResponse(success=True, data=UserResponse.model_validate(user))


@router.post("/login", response_model=ApiResponse[UserResponse])
async def login(body: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Login with Firebase token. Auto-registers if user doesn't exist."""
    payload = _decode_firebase_token(body.firebase_token)
    firebase_uid = payload.get("sub") or payload.get("user_id")
    email = payload.get("email", "")

    if not firebase_uid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Token 缺少使用者 ID",
        )

    result = await db.execute(
        select(User).where(User.firebase_uid == firebase_uid)
    )
    user = result.scalar_one_or_none()

    if user is None:
        # Auto-register on first login
        user = User(
            firebase_uid=firebase_uid,
            email=email,
            display_name=payload.get("name"),
        )
        db.add(user)
        await db.flush()
        await db.refresh(user)

    return ApiResponse(success=True, data=UserResponse.model_validate(user))


@router.get("/me", response_model=ApiResponse[UserResponse])
async def get_me(user: User = Depends(get_current_user)):
    """Get current user profile."""
    return ApiResponse(success=True, data=UserResponse.model_validate(user))
