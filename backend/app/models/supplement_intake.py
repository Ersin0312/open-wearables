from datetime import datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import ForeignKey, Index, Numeric
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, str_32


class SupplementIntake(BaseDbModel):
    """A single supplement intake event (the actual log entry).

    `taken_at` is when the user actually took it (may differ from created_at if
    backdated). `created_at` (from BaseDbModel) is when it was logged.
    Optional `stack_id` links back to the stack that produced this intake
    (when logged via "log stack now" flow) — useful for Coach analysis.
    """

    __tablename__ = "supplement_intake"
    __table_args__ = (
        Index("ix_supplement_intake_user_taken", "user_id", "taken_at"),
        Index("ix_supplement_intake_supplement", "supplement_id"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]
    supplement_id: Mapped[UUID] = mapped_column(
        ForeignKey("supplement.id", ondelete="RESTRICT"),
    )
    stack_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("supplement_stack.id", ondelete="SET NULL"),
        nullable=True,
    )

    taken_at: Mapped[datetime]
    dose: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    unit: Mapped[str_32]
    notes: Mapped[str | None] = mapped_column(nullable=True)
