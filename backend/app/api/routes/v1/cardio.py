"""Cardio-log endpoints: manually log Zone-2 / interval bouts, list, delete."""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from app.database import DbSession
from app.models import CardioSession
from app.schemas.model_crud.cardio import CardioSessionCreate, CardioSessionResponse
from app.services import ApiKeyDep

router = APIRouter()


@router.get("/users/{user_id}/cardio", response_model=list[CardioSessionResponse])
def list_cardio(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    start_date: datetime | None = Query(None),
    end_date: datetime | None = Query(None),
    limit: int = Query(200, ge=1, le=500),
):
    stmt = select(CardioSession).where(CardioSession.user_id == user_id)
    if start_date:
        stmt = stmt.where(CardioSession.performed_at >= start_date)
    if end_date:
        stmt = stmt.where(CardioSession.performed_at <= end_date)
    stmt = stmt.order_by(CardioSession.performed_at.desc()).limit(limit)
    return db.execute(stmt).scalars().all()


@router.post("/users/{user_id}/cardio", status_code=201, response_model=CardioSessionResponse)
def create_cardio(user_id: UUID, payload: CardioSessionCreate, db: DbSession, _api_key: ApiKeyDep):
    entry = CardioSession(
        id=payload.id,
        user_id=user_id,
        kind=payload.kind,
        performed_at=payload.performed_at,
        duration_min=payload.duration_min,
        avg_hr=payload.avg_hr,
        distance_km=payload.distance_km,
        notes=payload.notes,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.delete("/users/{user_id}/cardio/{entry_id}", response_model=CardioSessionResponse)
def delete_cardio(user_id: UUID, entry_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    entry = db.get(CardioSession, entry_id)
    if not entry or entry.user_id != user_id:
        raise HTTPException(status_code=404, detail="Entry not found")
    db.delete(entry)
    db.commit()
    return entry
