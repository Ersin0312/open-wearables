from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class CardioSessionBase(BaseModel):
    kind: str = Field("zone2", max_length=100)
    performed_at: datetime = Field(default_factory=lambda: datetime.now().astimezone())
    duration_min: Decimal = Field(..., ge=0, decimal_places=1)
    avg_hr: int | None = Field(None, ge=0, le=250)
    distance_km: Decimal | None = Field(None, ge=0, decimal_places=2)
    notes: str | None = None


class CardioSessionCreate(CardioSessionBase):
    id: UUID = Field(default_factory=uuid4)


class CardioSessionResponse(CardioSessionBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    model_config = {"from_attributes": True}
