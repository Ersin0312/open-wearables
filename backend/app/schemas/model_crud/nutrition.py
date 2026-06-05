from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class NutritionEntryBase(BaseModel):
    name: str = Field(..., max_length=100)
    eaten_at: datetime = Field(default_factory=lambda: datetime.now().astimezone())
    quantity_g: Decimal | None = Field(None, ge=0, decimal_places=2)
    calories: Decimal = Field(..., ge=0, decimal_places=2)
    protein_g: Decimal | None = Field(None, ge=0, decimal_places=2)
    carbs_g: Decimal | None = Field(None, ge=0, decimal_places=2)
    fat_g: Decimal | None = Field(None, ge=0, decimal_places=2)
    source: str | None = None
    notes: str | None = None


class NutritionEntryCreate(NutritionEntryBase):
    id: UUID = Field(default_factory=uuid4)


class NutritionEntryResponse(NutritionEntryBase):
    id: UUID
    user_id: UUID
    created_at: datetime

    model_config = {"from_attributes": True}
