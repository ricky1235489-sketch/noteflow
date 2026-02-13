from typing import Generic, TypeVar, Optional
from pydantic import BaseModel

T = TypeVar("T")


class ApiResponse(BaseModel, Generic[T]):
    success: bool
    data: Optional[T] = None
    error: Optional[str] = None


class PaginatedMeta(BaseModel):
    total: int
    page: int
    limit: int


class PaginatedResponse(BaseModel, Generic[T]):
    success: bool
    data: Optional[list[T]] = None
    error: Optional[str] = None
    meta: Optional[PaginatedMeta] = None
