from decimal import Decimal
from uuid import UUID

from sqlalchemy import Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, Unique, str_32, str_100


class Supplement(BaseDbModel):
    """Supplement library entry — defaults for a substance (not a brand/SKU).

    Pre-seeded with common bodybuilding / health basics; users can add custom
    entries (e.g. brand-specific or niche supplements).
    """

    __tablename__ = "supplement"
    __table_args__ = (
        Index("ix_supplement_category", "category"),
        Index("ix_supplement_created_by_user", "created_by_user_id"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    name: Mapped[Unique[str_100]]
    brand: Mapped[str | None] = mapped_column(nullable=True)  # manufacturer / Hersteller
    category: Mapped[str_32]
    default_dose: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    default_unit: Mapped[str_32]  # "mg", "g", "ml", "iu", "capsule", "tablet", "scoop", "drop"
    # Recommended daily intake (DGE / Naturheilpraxis orientation) — drives the
    # "% of daily dose reached today" display. Same unit as default_unit.
    recommended_daily_dose: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    notes: Mapped[str | None] = mapped_column(nullable=True)  # purpose / effects hint
    is_seeded: Mapped[bool] = mapped_column(default=False)
    created_by_user_id: Mapped[FKUser | None] = mapped_column(nullable=True)
