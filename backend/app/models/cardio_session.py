from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, str_100


class CardioSession(BaseDbModel):
    """A manually logged cardio bout (Zone-2, intervals, etc.). Complements the
    auto-synced WHOOP workouts for gym cardio that the strap may not capture."""

    __tablename__ = "cardio_session"
    __table_args__ = (
        Index("ix_cardio_session_user_performed", "user_id", "performed_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]

    kind: Mapped[str_100]                       # "zone2" | "intervals" | "other"
    performed_at: Mapped[datetime]
    duration_min: Mapped[Decimal] = mapped_column(Numeric(6, 1))
    avg_hr: Mapped[int | None] = mapped_column(nullable=True)
    distance_km: Mapped[Decimal | None] = mapped_column(Numeric(6, 2), nullable=True)
    notes: Mapped[str | None] = mapped_column(nullable=True)
