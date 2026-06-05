"""Nutrition log endpoints: log food/meal entries, list them, delete them.

Food lookup (Open Food Facts) happens client-side (no key needed); only the
chosen, already-resolved entry is persisted here so totals + the coach can use it.
"""

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from app.database import DbSession
from app.models import NutritionEntry
from app.schemas.model_crud.nutrition import NutritionEntryCreate, NutritionEntryResponse
from app.services import ApiKeyDep

router = APIRouter()


@router.get("/users/{user_id}/nutrition", response_model=list[NutritionEntryResponse])
def list_nutrition(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    start_date: datetime | None = Query(None),
    end_date: datetime | None = Query(None),
    limit: int = Query(200, ge=1, le=500),
):
    stmt = select(NutritionEntry).where(NutritionEntry.user_id == user_id)
    if start_date:
        stmt = stmt.where(NutritionEntry.eaten_at >= start_date)
    if end_date:
        stmt = stmt.where(NutritionEntry.eaten_at <= end_date)
    stmt = stmt.order_by(NutritionEntry.eaten_at.desc()).limit(limit)
    return db.execute(stmt).scalars().all()


@router.post(
    "/users/{user_id}/nutrition",
    status_code=201,
    response_model=NutritionEntryResponse,
)
def create_nutrition(
    user_id: UUID,
    payload: NutritionEntryCreate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    entry = NutritionEntry(
        id=payload.id,
        user_id=user_id,
        name=payload.name,
        eaten_at=payload.eaten_at,
        quantity_g=payload.quantity_g,
        calories=payload.calories,
        protein_g=payload.protein_g,
        carbs_g=payload.carbs_g,
        fat_g=payload.fat_g,
        source=payload.source,
        notes=payload.notes,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.delete("/users/{user_id}/nutrition/{entry_id}", response_model=NutritionEntryResponse)
def delete_nutrition(user_id: UUID, entry_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    entry = db.get(NutritionEntry, entry_id)
    if not entry or entry.user_id != user_id:
        raise HTTPException(status_code=404, detail="Entry not found")
    db.delete(entry)
    db.commit()
    return entry
