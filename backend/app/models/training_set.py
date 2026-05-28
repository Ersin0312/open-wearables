from uuid import UUID

from sqlalchemy import ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import BaseDbModel
from app.mappings import ManyToOne, PrimaryKey, numeric_5_2


class TrainingSet(BaseDbModel):
    """A single set within a training session.

    `created_at` (inherited from BaseDbModel) is the live timestamp when the
    set was logged. Differences between consecutive sets' `created_at` give
    us rest times for free.
    """

    __tablename__ = "training_set"
    __table_args__ = (
        Index("ix_training_set_session", "session_id"),
        Index("ix_training_set_exercise_created", "exercise_id", "created_at"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    session_id: Mapped[UUID] = mapped_column(
        ForeignKey("training_session.id", ondelete="CASCADE"),
    )
    exercise_id: Mapped[UUID] = mapped_column(
        ForeignKey("exercise.id", ondelete="RESTRICT"),
    )

    set_number: Mapped[int]  # 1-based, per (session, exercise) pair
    reps: Mapped[int]
    weight_kg: Mapped[numeric_5_2]
    rpe: Mapped[numeric_5_2 | None] = mapped_column(nullable=True)  # Rate of Perceived Exertion 1.0-10.0
    notes: Mapped[str | None] = mapped_column(nullable=True)

    session: Mapped[ManyToOne["TrainingSession"]] = relationship(
        "TrainingSession",
        back_populates="sets",
    )
