from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field

Equipment = Literal["machine", "barbell", "dumbbell", "cable", "bodyweight"]
MuscleGroup = Literal[
    "chest",
    "back",
    "shoulders",
    "biceps",
    "triceps",
    "legs",
    "core",
    "glutes",
    "fullbody",
]
SplitTag = Literal["push", "pull", "legs", "core"]


class ExerciseBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    equipment: Equipment
    primary_muscle_group: MuscleGroup
    default_split_tag: SplitTag
    image_url: str | None = None


class ExerciseCreate(ExerciseBase):
    """User-facing create — id and is_seeded are server-controlled."""

    id: UUID = Field(default_factory=uuid4)
    is_seeded: bool = False
    created_by_user_id: UUID | None = None


class ExerciseUpdate(BaseModel):
    """All fields optional for partial update."""

    name: str | None = Field(None, min_length=1, max_length=100)
    equipment: Equipment | None = None
    primary_muscle_group: MuscleGroup | None = None
    default_split_tag: SplitTag | None = None
    image_url: str | None = None


class ExerciseResponse(ExerciseBase):
    id: UUID
    is_seeded: bool
    created_by_user_id: UUID | None
    created_at: datetime

    model_config = {"from_attributes": True}
