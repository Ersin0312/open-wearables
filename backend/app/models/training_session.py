from datetime import datetime
from uuid import UUID

from sqlalchemy import Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import BaseDbModel
from app.mappings import FKUser, OneToMany, PrimaryKey, str_32


class TrainingSession(BaseDbModel):
    """A single training session (Push/Pull/Legs/Custom).

    Live-mode pattern: `started_at` is set on creation, `ended_at` is null
    until the user explicitly ends the session. Sets are added incrementally
    via the `sets` relationship.
    """

    __tablename__ = "training_session"
    __table_args__ = (
        Index("ix_training_session_user_started", "user_id", "started_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]

    started_at: Mapped[datetime]
    ended_at: Mapped[datetime | None] = mapped_column(nullable=True)

    split_tag: Mapped[str_32]  # "push" | "pull" | "legs" | "custom"
    notes: Mapped[str | None] = mapped_column(nullable=True)

    sets: Mapped[OneToMany["TrainingSet"]] = relationship(
        "TrainingSet",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="TrainingSet.created_at",
    )
