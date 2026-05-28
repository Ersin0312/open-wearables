from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, Field

SessionSplitTag = Literal["push", "pull", "legs", "custom"]


class TrainingSessionBase(BaseModel):
    split_tag: SessionSplitTag
    notes: str | None = None


class TrainingSessionCreate(TrainingSessionBase):
    """Start a new live session. started_at defaults to server now() if omitted."""

    id: UUID = Field(default_factory=uuid4)
    user_id: UUID
    started_at: datetime = Field(default_factory=lambda: datetime.now().astimezone())


class TrainingSessionUpdate(BaseModel):
    """Partial update: only split_tag/notes — see TrainingSessionEnd for ending."""

    split_tag: SessionSplitTag | None = None
    notes: str | None = None


class TrainingSessionEnd(BaseModel):
    """Mark session as ended. If `ended_at` omitted, server uses now()."""

    ended_at: datetime | None = None


class TrainingSessionResponse(TrainingSessionBase):
    id: UUID
    user_id: UUID
    started_at: datetime
    ended_at: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}
