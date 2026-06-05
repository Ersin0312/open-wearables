from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


# --- Bloodwork ---

class BloodworkEntryBase(BaseModel):
    marker: str = Field(..., max_length=100)
    value: Decimal = Field(..., decimal_places=3)
    unit: str = Field(..., max_length=100)
    taken_at: datetime = Field(default_factory=lambda: datetime.now().astimezone())
    notes: str | None = None


class BloodworkEntryCreate(BloodworkEntryBase):
    id: UUID = Field(default_factory=uuid4)


class BloodworkEntryResponse(BloodworkEntryBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    model_config = {"from_attributes": True}


# --- Pull-ups ---

class PullupEntryBase(BaseModel):
    reps: int = Field(..., ge=0, le=100)
    added_weight_kg: Decimal | None = Field(None, ge=0, decimal_places=2)
    performed_at: datetime = Field(default_factory=lambda: datetime.now().astimezone())
    notes: str | None = None


class PullupEntryCreate(PullupEntryBase):
    id: UUID = Field(default_factory=uuid4)


class PullupEntryResponse(PullupEntryBase):
    id: UUID
    user_id: UUID
    created_at: datetime
    model_config = {"from_attributes": True}
