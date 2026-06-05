from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel


class BodyScanResponse(BaseModel):
    id: UUID
    user_id: UUID
    measured_at: datetime
    source: str
    weight_kg: Decimal | None = None
    bmi: Decimal | None = None
    body_fat_percent: Decimal | None = None
    muscle_mass_kg: Decimal | None = None
    body_water_percent: Decimal | None = None
    bone_mass_kg: Decimal | None = None
    bmr_kcal: Decimal | None = None
    visceral_fat: Decimal | None = None
    subcutaneous_fat_percent: Decimal | None = None
    protein_percent: Decimal | None = None

    model_config = {"from_attributes": True}


class RenphoSyncResponse(BaseModel):
    enabled: bool
    new_scans: int
    total_scans: int
