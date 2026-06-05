from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, str_100


class BloodworkEntry(BaseDbModel):
    """One lab marker reading (e.g. Testosteron 5.2 ng/ml) at a point in time.
    One row per marker per draw, so a panel is several rows sharing taken_at."""

    __tablename__ = "bloodwork_entry"
    __table_args__ = (
        Index("ix_bloodwork_entry_user_taken", "user_id", "taken_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]

    marker: Mapped[str_100]
    value: Mapped[Decimal] = mapped_column(Numeric(12, 3))
    unit: Mapped[str_100]
    taken_at: Mapped[datetime]
    notes: Mapped[str | None] = mapped_column(nullable=True)
