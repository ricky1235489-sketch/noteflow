"""Rate limiting for transcription usage."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..core.auth import get_current_user
from ..core.exceptions import RateLimitExceeded
from ..database import get_db
from ..models.user import User


class RateLimiter:
    LIMITS = {
        False: {  # Free tier (is_pro=False)
            "monthly_conversions": settings.free_monthly_conversions,
            "max_duration_seconds": settings.free_max_duration_seconds,
        },
        True: {  # Pro tier (is_pro=True)
            "monthly_conversions": 999999,
            "max_duration_seconds": settings.pro_max_duration_seconds,
        },
    }

    @staticmethod
    async def _reset_if_new_month(user: User, db: AsyncSession) -> None:
        """Reset monthly counter if we're in a new month."""
        now = datetime.now(timezone.utc)
        reset_date = user.monthly_reset_date
        if reset_date is None or (
            now.year > reset_date.year
            or (now.year == reset_date.year and now.month > reset_date.month)
        ):
            user.monthly_conversions_used = 0
            user.monthly_reset_date = now
            await db.flush()

    @classmethod
    async def check_and_increment(
        cls, user: User, db: AsyncSession
    ) -> None:
        """Check rate limit and increment usage. Raises RateLimitExceeded."""
        await cls._reset_if_new_month(user, db)

        limits = cls.LIMITS[user.is_pro]

        if user.monthly_conversions_used >= limits["monthly_conversions"]:
            raise RateLimitExceeded(
                f"已達本月轉換上限 ({limits['monthly_conversions']} 次)"
            )

        user.monthly_conversions_used += 1
        await db.flush()

    @classmethod
    def get_max_duration(cls, user: User) -> int:
        return cls.LIMITS[user.is_pro]["max_duration_seconds"]

    @classmethod
    def get_monthly_limit(cls, user: User) -> int:
        return cls.LIMITS[user.is_pro]["monthly_conversions"]


rate_limiter = RateLimiter()
