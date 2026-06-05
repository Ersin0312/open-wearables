"""Renpho cloud sync + body-scan history endpoints."""

from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import select

from app.database import DbSession
from app.models import BodyScan
from app.schemas.model_crud.body_scan import BodyScanResponse, RenphoSyncResponse
from app.services import ApiKeyDep
from app.services.renpho_service import renpho_service

router = APIRouter()


@router.get("/users/{user_id}/renpho/status")
def renpho_status(user_id: UUID, _api_key: ApiKeyDep) -> dict:
    """Whether Renpho credentials are configured server-side."""
    return {"enabled": renpho_service.is_enabled()}


@router.post("/users/{user_id}/renpho/sync", response_model=RenphoSyncResponse)
async def renpho_sync(user_id: UUID, db: DbSession, _api_key: ApiKeyDep) -> RenphoSyncResponse:
    """Pull the latest scans from the Renpho cloud and store new ones."""
    if not renpho_service.is_enabled():
        raise HTTPException(status_code=503, detail="Renpho nicht konfiguriert (RENPHO_EMAIL/RENPHO_PASSWORD fehlen).")
    try:
        rows = await renpho_service.fetch_latest_measurements()
    except ValueError as e:
        raise HTTPException(status_code=502, detail=str(e))
    new_count = renpho_service.sync(db, user_id, rows)
    total = db.query(BodyScan).filter(BodyScan.user_id == user_id).count()
    return RenphoSyncResponse(enabled=True, new_scans=new_count, total_scans=total)


@router.get("/users/{user_id}/body-scans", response_model=list[BodyScanResponse])
def list_body_scans(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    limit: int = Query(180, ge=1, le=500),
):
    stmt = (
        select(BodyScan)
        .where(BodyScan.user_id == user_id)
        .order_by(BodyScan.measured_at.desc())
        .limit(limit)
    )
    return db.execute(stmt).scalars().all()
