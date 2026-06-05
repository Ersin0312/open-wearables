from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, str_100


class NutritionEntry(BaseDbModel):
    """A single logged food/meal entry. Macros are per the logged quantity
    (already multiplied), so totals are a simple sum. Source is the lookup
    provider (e.g. 'openfoodfacts') or 'manual'."""

    __tablename__ = "nutrition_entry"
    __table_args__ = (
        Index("ix_nutrition_entry_user_eaten", "user_id", "eaten_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]

    name: Mapped[str_100]
    eaten_at: Mapped[datetime]
    quantity_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    calories: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    protein_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    carbs_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    fat_g: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    source: Mapped[str | None] = mapped_column(nullable=True)
    notes: Mapped[str | None] = mapped_column(nullable=True)
