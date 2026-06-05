from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, str_100


class BodyScan(BaseDbModel):
    """A full smart-scale measurement (Renpho), including metrics Apple Health
    can't carry: body water %, visceral fat, bone mass, BMR, protein %."""

    __tablename__ = "body_scan"
    __table_args__ = (
        Index("ix_body_scan_user_measured", "user_id", "measured_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]

    measured_at: Mapped[datetime]
    source: Mapped[str_100]

    weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(6, 2), nullable=True)
    bmi: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    body_fat_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    muscle_mass_kg: Mapped[Decimal | None] = mapped_column(Numeric(6, 2), nullable=True)
    body_water_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    bone_mass_kg: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    bmr_kcal: Mapped[Decimal | None] = mapped_column(Numeric(7, 1), nullable=True)
    visceral_fat: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    subcutaneous_fat_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    protein_percent: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
