from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class SupplementIntakeBase(BaseModel):
    supplement_id: UUID
    taken_at: datetime = Field(default_factory=lambda: datetime.now().astimezone())
    dose: Decimal = Field(..., ge=0, decimal_places=2)
    unit: str = Field(..., max_length=32)
    notes: str | None = None
    stack_id: UUID | None = None


class SupplementIntakeCreate(SupplementIntakeBase):
    id: UUID = Field(default_factory=uuid4)


class SupplementIntakeUpdate(BaseModel):
    supplement_id: UUID | None = None
    taken_at: datetime | None = None
    dose: Decimal | None = Field(None, ge=0, decimal_places=2)
    unit: str | None = None
    notes: str | None = None


class SupplementIntakeResponse(SupplementIntakeBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    model_config = {"from_attributes": True}
