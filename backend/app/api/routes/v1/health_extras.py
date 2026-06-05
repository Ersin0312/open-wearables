"""Bloodwork + pull-up benchmark endpoints (manual log, list, delete)."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from app.database import DbSession
from app.models import BloodworkEntry, PullupEntry
from app.schemas.model_crud.health_extras import (
    BloodworkEntryCreate,
    BloodworkEntryResponse,
    PullupEntryCreate,
    PullupEntryResponse,
)
from app.services import ApiKeyDep

router = APIRouter()


# --- Bloodwork ---

@router.get("/users/{user_id}/bloodwork", response_model=list[BloodworkEntryResponse])
def list_bloodwork(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    marker: str | None = Query(None),
    limit: int = Query(500, ge=1, le=1000),
):
    stmt = select(BloodworkEntry).where(BloodworkEntry.user_id == user_id)
    if marker:
        stmt = stmt.where(BloodworkEntry.marker == marker)
    stmt = stmt.order_by(BloodworkEntry.taken_at.desc()).limit(limit)
    return db.execute(stmt).scalars().all()


@router.post("/users/{user_id}/bloodwork", status_code=201, response_model=BloodworkEntryResponse)
def create_bloodwork(user_id: UUID, payload: BloodworkEntryCreate, db: DbSession, _api_key: ApiKeyDep):
    entry = BloodworkEntry(
        id=payload.id, user_id=user_id, marker=payload.marker, value=payload.value,
        unit=payload.unit, taken_at=payload.taken_at, notes=payload.notes,
    )
    db.add(entry); db.commit(); db.refresh(entry)
    return entry


@router.delete("/users/{user_id}/bloodwork/{entry_id}", response_model=BloodworkEntryResponse)
def delete_bloodwork(user_id: UUID, entry_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    entry = db.get(BloodworkEntry, entry_id)
    if not entry or entry.user_id != user_id:
        raise HTTPException(status_code=404, detail="Entry not found")
    db.delete(entry); db.commit()
    return entry


# --- Pull-ups ---

@router.get("/users/{user_id}/pullups", response_model=list[PullupEntryResponse])
def list_pullups(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    limit: int = Query(200, ge=1, le=500),
):
    stmt = (
        select(PullupEntry)
        .where(PullupEntry.user_id == user_id)
        .order_by(PullupEntry.performed_at.desc())
        .limit(limit)
    )
    return db.execute(stmt).scalars().all()


@router.post("/users/{user_id}/pullups", status_code=201, response_model=PullupEntryResponse)
def create_pullup(user_id: UUID, payload: PullupEntryCreate, db: DbSession, _api_key: ApiKeyDep):
    entry = PullupEntry(
        id=payload.id, user_id=user_id, reps=payload.reps,
        added_weight_kg=payload.added_weight_kg, performed_at=payload.performed_at, notes=payload.notes,
    )
    db.add(entry); db.commit(); db.refresh(entry)
    return entry


@router.delete("/users/{user_id}/pullups/{entry_id}", response_model=PullupEntryResponse)
def delete_pullup(user_id: UUID, entry_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    entry = db.get(PullupEntry, entry_id)
    if not entry or entry.user_id != user_id:
        raise HTTPException(status_code=404, detail="Entry not found")
    db.delete(entry); db.commit()
    return entry
