from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field


class SupplementStackItemCreate(BaseModel):
    supplement_id: UUID
    order_index: int = 0
    dose: Decimal | None = Field(None, ge=0, decimal_places=2)  # null → use supplement.default_dose
    unit: str | None = None  # null → use supplement.default_unit


class SupplementStackItemResponse(BaseModel):
    id: UUID
    stack_id: UUID
    supplement_id: UUID
    order_index: int
    dose: Decimal | None
    unit: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class SupplementStackBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    notes: str | None = None


class SupplementStackCreate(SupplementStackBase):
    id: UUID = Field(default_factory=uuid4)
    items: list[SupplementStackItemCreate] = Field(default_factory=list)


class SupplementStackUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    notes: str | None = None
    # If items is provided, it REPLACES all existing items (full sync semantics).
    items: list[SupplementStackItemCreate] | None = None


class SupplementStackResponse(SupplementStackBase):
    id: UUID
    user_id: UUID
    items: list[SupplementStackItemResponse]
    created_at: datetime

    model_config = {"from_attributes": True}
