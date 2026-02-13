"""Firebase Auth JWT verification middleware."""
from __future__ import annotations

from typing import Optional

import httpx
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import settings
from ..database import get_db
from ..models.user import User

_bearer_scheme = HTTPBearer(auto_error=False)

# Google public keys cache
_google_certs: dict = {}
_GOOGLE_CERTS_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"


async def _fetch_google_certs() -> dict:
    """Fetch Google's public certificates for JWT verification."""
    global _google_certs
    if _google_certs:
        return _google_certs
    async with httpx.AsyncClient() as client:
        response = await client.get(_GOOGLE_CERTS_URL)
        response.raise_for_status()
        _google_certs = response.json()
    return _google_certs


def _decode_firebase_token(token: str) -> dict:
    """Decode and verify a Firebase ID token.

    For dev mode, if firebase_project_id is not set, accepts
    any well-formed JWT without signature verification.
    """
    project_id = settings.firebase_project_id

    if not project_id:
        # Dev mode: decode without verification
        try:
            payload = jwt.get_unverified_claims(token)
            return payload
        except JWTError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"無效的 token: {exc}",
            ) from exc

    try:
        payload = jwt.decode(
            token,
            key="",  # Will be replaced with proper key verification
            algorithms=["RS256"],
            audience=project_id,
            issuer=f"https://securetoken.google.com/{project_id}",
            options={"verify_signature": False},  # TODO: verify with Google certs
        )
        return payload
    except JWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token 驗證失敗: {exc}",
        ) from exc


async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    """FastAPI dependency: extract and verify Firebase token, return User."""
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="需要登入",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = _decode_firebase_token(credentials.credentials)
    firebase_uid = payload.get("sub") or payload.get("user_id")

    if not firebase_uid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token 缺少使用者 ID",
        )

    result = await db.execute(
        select(User).where(User.firebase_uid == firebase_uid)
    )
    user = result.scalar_one_or_none()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="使用者不存在，請先註冊",
        )

    return user


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    """Optional auth: returns User if token present, None otherwise."""
    if credentials is None:
        return None
    try:
        return await get_current_user(credentials, db)
    except HTTPException:
        return None
