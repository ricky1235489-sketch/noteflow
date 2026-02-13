"""User endpoints — usage stats & subscription sync."""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from ...core.auth import get_current_user
from ...core.rate_limiter import RateLimiter
from ...database import get_db
from ...models.user import User
from ...schemas.common import ApiResponse

router = APIRouter(prefix="/users", tags=["users"])


class UsageResponse(BaseModel):
    monthly_conversions_used: int
    monthly_conversions_limit: int
    max_duration_seconds: int
    is_pro: bool
    reset_date: datetime

    model_config = {"from_attributes": True}


class SubscriptionSyncRequest(BaseModel):
    """Payload from RevenueCat webhook or client-side sync."""
    is_pro: bool
    revenucat_user_id: str | None = None


class SubscriptionSyncResponse(BaseModel):
    is_pro: bool
    monthly_conversions_limit: int
    max_duration_seconds: int


@router.get("/me/usage", response_model=ApiResponse[UsageResponse])
async def get_usage(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """取得當前使用者的使用量統計。"""
    # Reset counter if new month
    now = datetime.now(timezone.utc)
    reset_date = user.monthly_reset_date
    if reset_date is None or (
        now.year > reset_date.year
        or (now.year == reset_date.year and now.month > reset_date.month)
    ):
        user.monthly_conversions_used = 0
        user.monthly_reset_date = now
        await db.flush()

    return ApiResponse(
        success=True,
        data=UsageResponse(
            monthly_conversions_used=user.monthly_conversions_used,
            monthly_conversions_limit=RateLimiter.get_monthly_limit(user),
            max_duration_seconds=RateLimiter.get_max_duration(user),
            is_pro=user.is_pro,
            reset_date=user.monthly_reset_date,
        ),
    )


@router.post("/me/subscription", response_model=ApiResponse[SubscriptionSyncResponse])
async def sync_subscription(
    body: SubscriptionSyncRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """同步訂閱狀態（從 RevenueCat 客戶端或 webhook）。"""
    user.is_pro = body.is_pro
    await db.flush()

    return ApiResponse(
        success=True,
        data=SubscriptionSyncResponse(
            is_pro=user.is_pro,
            monthly_conversions_limit=RateLimiter.get_monthly_limit(user),
            max_duration_seconds=RateLimiter.get_max_duration(user),
        ),
    )
