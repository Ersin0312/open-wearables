from uuid import UUID

from sqlalchemy import Index
from sqlalchemy.orm import Mapped, mapped_column

from app.database import BaseDbModel
from app.mappings import FKUser, PrimaryKey, Unique, str_32, str_50, str_100


class Exercise(BaseDbModel):
    """Exercise library entry.

    Pre-seeded with Gym80 Sygnum equipment plus extensible by users.
    `is_seeded=True` marks library entries from the initial seed; user-created
    custom exercises have `is_seeded=False` and a non-null `created_by_user_id`.
    """

    __tablename__ = "exercise"
    __table_args__ = (
        Index("ix_exercise_split_tag", "default_split_tag"),
        Index("ix_exercise_muscle_group", "primary_muscle_group"),
        Index("ix_exercise_created_by_user", "created_by_user_id"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    name: Mapped[Unique[str_100]]
    equipment: Mapped[str_50]  # "machine" | "barbell" | "dumbbell" | "cable" | "bodyweight"
    primary_muscle_group: Mapped[str_32]  # "chest" | "back" | "shoulders" | "biceps" | "triceps" | "legs" | "core" | "glutes"
    default_split_tag: Mapped[str_32]  # "push" | "pull" | "legs" | "core"
    image_url: Mapped[str | None] = mapped_column(nullable=True)
    is_seeded: Mapped[bool] = mapped_column(default=False)
    created_by_user_id: Mapped[FKUser | None] = mapped_column(nullable=True)
