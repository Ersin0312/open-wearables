"""Training-log endpoints: exercises (library), training sessions, training sets.

Manual entry surface for strength training — pairs with auto-synced WHOOP data.
Exercise library is seeded with Gym80 Sygnum equipment plus user-extensible.
"""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from app.database import DbSession
from app.schemas.model_crud.training import (
    ExerciseCreate,
    ExerciseResponse,
    ExerciseUpdate,
    TrainingSessionCreate,
    TrainingSessionEnd,
    TrainingSessionResponse,
    TrainingSessionUpdate,
    TrainingSetCreate,
    TrainingSetResponse,
    TrainingSetUpdate,
)
from app.services import ApiKeyDep
from app.services.training_service import (
    exercise_service,
    training_session_service,
    training_set_service,
)

router = APIRouter()


# ------------------------- Exercise library -------------------------

@router.get("/training/exercises", response_model=list[ExerciseResponse])
def list_exercises(
    user_id: Annotated[UUID, Query(description="Returns seeded library + this user's customs")],
    db: DbSession,
    _api_key: ApiKeyDep,
    split_tag: str | None = Query(None, description="Filter: push | pull | legs | core"),
    muscle_group: str | None = Query(None, description="Filter: chest | back | shoulders | ..."),
    search: str | None = Query(None, description="Fuzzy name match"),
):
    return exercise_service.list_visible_for_user(db, user_id, split_tag, muscle_group, search)


@router.post(
    "/training/exercises",
    status_code=status.HTTP_201_CREATED,
    response_model=ExerciseResponse,
)
def create_exercise(payload: ExerciseCreate, db: DbSession, _api_key: ApiKeyDep):
    """Create a user-custom exercise. Seeded library entries are managed via the seed script."""
    if payload.is_seeded:
        raise HTTPException(status_code=400, detail="is_seeded=True is reserved for the seed script")
    return exercise_service.create(db, payload)


@router.patch("/training/exercises/{exercise_id}", response_model=ExerciseResponse)
def update_exercise(exercise_id: UUID, payload: ExerciseUpdate, db: DbSession, _api_key: ApiKeyDep):
    return exercise_service.update(db, exercise_id, payload, raise_404=True)


@router.delete("/training/exercises/{exercise_id}", response_model=ExerciseResponse)
def delete_exercise(exercise_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    existing = exercise_service.get(db, exercise_id, raise_404=True)
    if existing and existing.is_seeded:
        raise HTTPException(status_code=400, detail="Cannot delete seeded library entries")
    return exercise_service.delete(db, exercise_id, raise_404=True)


# ------------------------- Training sessions -------------------------

@router.post(
    "/users/{user_id}/training/sessions",
    status_code=status.HTTP_201_CREATED,
    response_model=TrainingSessionResponse,
)
def start_session(
    user_id: UUID,
    payload: TrainingSessionCreate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    """Start a new training session (live mode). ended_at stays null until /end is called."""
    if payload.user_id != user_id:
        raise HTTPException(status_code=400, detail="payload.user_id must match URL user_id")
    return training_session_service.create(db, payload)


@router.get("/users/{user_id}/training/sessions", response_model=list[TrainingSessionResponse])
def list_sessions(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    start_date: datetime | None = Query(None),
    end_date: datetime | None = Query(None),
    split_tag: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    return training_session_service.list_for_user(
        db, user_id, start_date, end_date, split_tag, limit, offset
    )


@router.get(
    "/users/{user_id}/training/sessions/{session_id}",
    response_model=TrainingSessionResponse,
)
def get_session(user_id: UUID, session_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    session = training_session_service.get_with_sets(db, session_id)
    if session.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return session


@router.patch(
    "/users/{user_id}/training/sessions/{session_id}",
    response_model=TrainingSessionResponse,
)
def update_session(
    user_id: UUID,
    session_id: UUID,
    payload: TrainingSessionUpdate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    existing = training_session_service.get(db, session_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_session_service.update(db, session_id, payload, raise_404=True)


@router.post(
    "/users/{user_id}/training/sessions/{session_id}/end",
    response_model=TrainingSessionResponse,
)
def end_session(
    user_id: UUID,
    session_id: UUID,
    payload: TrainingSessionEnd,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    """Mark a live session as ended. If ended_at omitted, server uses now()."""
    existing = training_session_service.get(db, session_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_session_service.end_session(db, session_id, payload.ended_at)


@router.post(
    "/users/{user_id}/training/sessions/{session_id}/reopen",
    response_model=TrainingSessionResponse,
)
def reopen_session(user_id: UUID, session_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    """Re-open an ended session so the user can edit / add sets."""
    existing = training_session_service.get(db, session_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_session_service.reopen_session(db, session_id)


@router.post(
    "/users/{user_id}/training/sessions/{session_id}/duplicate",
    status_code=status.HTTP_201_CREATED,
    response_model=TrainingSessionResponse,
)
def duplicate_session(user_id: UUID, session_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    """Clone an existing session + its sets into a fresh live session (started_at=now)."""
    return training_session_service.duplicate_session(db, session_id, user_id)


@router.delete(
    "/users/{user_id}/training/sessions/{session_id}",
    response_model=TrainingSessionResponse,
)
def delete_session(user_id: UUID, session_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    existing = training_session_service.get(db, session_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_session_service.delete(db, session_id, raise_404=True)


@router.get(
    "/users/{user_id}/training/last-session",
    response_model=TrainingSessionResponse | None,
)
def get_last_session(
    user_id: UUID,
    split_tag: str,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    """For the 'repeat last session' shortcut — returns the last session with given split_tag."""
    return training_session_service.get_last_for_user_and_split(db, user_id, split_tag)


# ------------------------- Training sets -------------------------

@router.post(
    "/users/{user_id}/training/sessions/{session_id}/sets",
    status_code=status.HTTP_201_CREATED,
    response_model=TrainingSetResponse,
)
def add_set(
    user_id: UUID,
    session_id: UUID,
    payload: TrainingSetCreate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    """Live-log a set during a session. created_at = server timestamp (used for rest-time analytics)."""
    session = training_session_service.get(db, session_id, raise_404=True)
    if session.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_set_service.add_set(db, session_id, payload)


@router.get(
    "/users/{user_id}/training/sessions/{session_id}/sets",
    response_model=list[TrainingSetResponse],
)
def list_sets(user_id: UUID, session_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    session = training_session_service.get(db, session_id, raise_404=True)
    if session.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_set_service.list_for_session(db, session_id)


@router.patch(
    "/users/{user_id}/training/sessions/{session_id}/sets/{set_id}",
    response_model=TrainingSetResponse,
)
def update_set(
    user_id: UUID,
    session_id: UUID,
    set_id: UUID,
    payload: TrainingSetUpdate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    session = training_session_service.get(db, session_id, raise_404=True)
    if session.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_set_service.update(db, set_id, payload, raise_404=True)


@router.delete(
    "/users/{user_id}/training/sessions/{session_id}/sets/{set_id}",
    response_model=TrainingSetResponse,
)
def delete_set(user_id: UUID, session_id: UUID, set_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    session = training_session_service.get(db, session_id, raise_404=True)
    if session.user_id != user_id:
        raise HTTPException(status_code=404, detail="Session not found for this user")
    return training_set_service.delete(db, set_id, raise_404=True)
