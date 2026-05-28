from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class TrainingSetBase(BaseModel):
    exercise_id: UUID
    set_number: int = Field(..., ge=1, le=50)
    reps: int = Field(..., ge=0, le=500)
    weight_kg: Decimal = Field(..., ge=0, le=999.99, decimal_places=2)
    rpe: Decimal | None = Field(None, ge=1, le=10, decimal_places=2)
    notes: str | None = None


class TrainingSetCreate(TrainingSetBase):
    """Add a set to a session. session_id comes from URL path."""

    id: UUID = Field(default_factory=uuid4)


class TrainingSetUpdate(BaseModel):
    """Partial update of an existing set."""

    exercise_id: UUID | None = None
    set_number: int | None = Field(None, ge=1, le=50)
    reps: int | None = Field(None, ge=0, le=500)
    weight_kg: Decimal | None = Field(None, ge=0, le=999.99, decimal_places=2)
    rpe: Decimal | None = Field(None, ge=1, le=10, decimal_places=2)
    notes: str | None = None


class TrainingSetResponse(TrainingSetBase):
    id: UUID
    session_id: UUID
    created_at: datetime

    model_config = {"from_attributes": True}
