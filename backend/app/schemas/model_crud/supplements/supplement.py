from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field

Category = Literal[
    "amino_acid",
    "vitamin",
    "mineral",
    "protein",
    "fatty_acid",
    "nootropic",
    "performance",
    "recovery",
    "other",
]

Unit = Literal["mg", "g", "ml", "iu", "capsule", "tablet", "scoop", "drop"]


class SupplementBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    brand: str | None = Field(None, max_length=100)
    category: Category
    default_dose: Decimal | None = Field(None, ge=0, decimal_places=2)
    default_unit: Unit
    recommended_daily_dose: Decimal | None = Field(None, ge=0, decimal_places=2)
    notes: str | None = None


class SupplementCreate(SupplementBase):
    id: UUID = Field(default_factory=uuid4)
    is_seeded: bool = False
    created_by_user_id: UUID | None = None


class SupplementUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    brand: str | None = Field(None, max_length=100)
    category: Category | None = None
    default_dose: Decimal | None = Field(None, ge=0, decimal_places=2)
    default_unit: Unit | None = None
    recommended_daily_dose: Decimal | None = Field(None, ge=0, decimal_places=2)
    notes: str | None = None


class SupplementResponse(SupplementBase):
    id: UUID
    is_seeded: bool
    created_by_user_id: UUID | None
    created_at: datetime

    model_config = {"from_attributes": True}
