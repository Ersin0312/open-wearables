from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey


class PullupEntry(BaseDbModel):
    """A pull-up benchmark: max clean reps in a set, optionally with added load.
    Tracks bodyweight strength progression alongside the machine work."""

    __tablename__ = "pullup_entry"
    __table_args__ = (
        Index("ix_pullup_entry_user_performed", "user_id", "performed_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]

    reps: Mapped[int]
    added_weight_kg: Mapped[Decimal | None] = mapped_column(Numeric(5, 2), nullable=True)
    performed_at: Mapped[datetime]
    notes: Mapped[str | None] = mapped_column(nullable=True)
