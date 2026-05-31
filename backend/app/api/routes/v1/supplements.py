"""Supplement-log endpoints: library, daily stacks, individual intakes.

Manual entry surface for tracking NEMs (Nahrungsergänzungsmittel). Designed
for quick-logging via predefined stacks ("Morning Stack" → one click logs
all items with the current timestamp).
"""

from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from app.database import DbSession
from app.models import SupplementIntake, SupplementStackItem
from app.schemas.model_crud.supplements import (
    SupplementCreate,
    SupplementIntakeCreate,
    SupplementIntakeResponse,
    SupplementIntakeUpdate,
    SupplementResponse,
    SupplementStackCreate,
    SupplementStackResponse,
    SupplementStackUpdate,
    SupplementUpdate,
)
from app.services import ApiKeyDep
from app.services.supplement_service import (
    supplement_intake_service,
    supplement_service,
    supplement_stack_service,
)

router = APIRouter()


# ------------------------- Supplement library -------------------------

@router.get("/supplements", response_model=list[SupplementResponse])
def list_supplements(
    user_id: Annotated[UUID, Query(description="Returns seeded library + this user's customs")],
    db: DbSession,
    _api_key: ApiKeyDep,
    category: str | None = Query(None, description="Filter: amino_acid | vitamin | mineral | ..."),
    search: str | None = Query(None, description="Fuzzy name match"),
):
    return supplement_service.list_visible_for_user(db, user_id, category, search)


@router.post(
    "/supplements",
    status_code=status.HTTP_201_CREATED,
    response_model=SupplementResponse,
)
def create_supplement(payload: SupplementCreate, db: DbSession, _api_key: ApiKeyDep):
    if payload.is_seeded:
        raise HTTPException(status_code=400, detail="is_seeded=True is reserved for the seed script")
    return supplement_service.create(db, payload)


@router.patch("/supplements/{supplement_id}", response_model=SupplementResponse)
def update_supplement(
    supplement_id: UUID,
    payload: SupplementUpdate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    return supplement_service.update(db, supplement_id, payload, raise_404=True)


@router.delete("/supplements/{supplement_id}", response_model=SupplementResponse)
def delete_supplement(supplement_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    """Delete a library entry (seeded or custom). Blocked with a clear 409 when
    the NEM is still referenced by logged intakes or stack items (FK RESTRICT),
    so the user gets a helpful message instead of a raw 500."""
    existing = supplement_service.get(db, supplement_id, raise_404=True)

    intake_count = db.query(SupplementIntake).filter(
        SupplementIntake.supplement_id == supplement_id
    ).count()
    if intake_count > 0:
        raise HTTPException(
            status_code=409,
            detail=(
                f"NEM wird noch von {intake_count} geloggten Einnahme(n) verwendet. "
                "Lösche zuerst die Einträge in der Tagesansicht."
            ),
        )

    stack_item_count = db.query(SupplementStackItem).filter(
        SupplementStackItem.supplement_id == supplement_id
    ).count()
    if stack_item_count > 0:
        raise HTTPException(
            status_code=409,
            detail=(
                f"NEM ist in {stack_item_count} Stack(s) enthalten. "
                "Entferne es zuerst aus den Stacks."
            ),
        )

    return supplement_service.delete(db, supplement_id, raise_404=True)


# ------------------------- Stacks -------------------------

@router.get(
    "/users/{user_id}/supplement-stacks",
    response_model=list[SupplementStackResponse],
)
def list_stacks(user_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    return supplement_stack_service.list_for_user(db, user_id)


@router.post(
    "/users/{user_id}/supplement-stacks",
    status_code=status.HTTP_201_CREATED,
    response_model=SupplementStackResponse,
)
def create_stack(
    user_id: UUID,
    payload: SupplementStackCreate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    return supplement_stack_service.create_with_items(db, user_id, payload)


@router.get(
    "/users/{user_id}/supplement-stacks/{stack_id}",
    response_model=SupplementStackResponse,
)
def get_stack(user_id: UUID, stack_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    stack = supplement_stack_service.get_with_items(db, stack_id)
    if stack.user_id != user_id:
        raise HTTPException(status_code=404, detail="Stack not found for this user")
    return stack


@router.patch(
    "/users/{user_id}/supplement-stacks/{stack_id}",
    response_model=SupplementStackResponse,
)
def update_stack(
    user_id: UUID,
    stack_id: UUID,
    payload: SupplementStackUpdate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    existing = supplement_stack_service.get(db, stack_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Stack not found for this user")
    return supplement_stack_service.update_with_items(db, stack_id, payload)


@router.delete(
    "/users/{user_id}/supplement-stacks/{stack_id}",
    response_model=SupplementStackResponse,
)
def delete_stack(user_id: UUID, stack_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    # Load with items and serialise the response BEFORE deleting. After
    # delete + commit the ORM instance is detached, so a lazy-load of `.items`
    # for the response_model would raise DetachedInstanceError (→ 500).
    existing = supplement_stack_service.get_with_items(db, stack_id)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Stack not found for this user")
    response = SupplementStackResponse.model_validate(existing)
    supplement_stack_service.delete(db, stack_id, raise_404=True)
    return response


@router.post(
    "/users/{user_id}/supplement-stacks/{stack_id}/log-now",
    status_code=status.HTTP_201_CREATED,
    response_model=list[SupplementIntakeResponse],
)
def log_stack_now(
    user_id: UUID,
    stack_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    taken_at: datetime | None = Query(None, description="Backdate the log to this timestamp; defaults to now"),
):
    """One-click: bulk-creates intakes for every item in the stack. `taken_at`
    lets the user backdate the log to a past day (forgotten entry)."""
    existing = supplement_stack_service.get(db, stack_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Stack not found for this user")
    return supplement_stack_service.log_stack_now(db, stack_id, user_id, when=taken_at)


# ------------------------- Individual intakes -------------------------

@router.get(
    "/users/{user_id}/supplement-intakes",
    response_model=list[SupplementIntakeResponse],
)
def list_intakes(
    user_id: UUID,
    db: DbSession,
    _api_key: ApiKeyDep,
    start_date: datetime | None = Query(None),
    end_date: datetime | None = Query(None),
    supplement_id: UUID | None = Query(None),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    return supplement_intake_service.list_for_user(
        db, user_id, start_date, end_date, supplement_id, limit, offset
    )


@router.post(
    "/users/{user_id}/supplement-intakes",
    status_code=status.HTTP_201_CREATED,
    response_model=SupplementIntakeResponse,
)
def add_intake(
    user_id: UUID,
    payload: SupplementIntakeCreate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    return supplement_intake_service.add_intake(db, user_id, payload)


@router.patch(
    "/users/{user_id}/supplement-intakes/{intake_id}",
    response_model=SupplementIntakeResponse,
)
def update_intake(
    user_id: UUID,
    intake_id: UUID,
    payload: SupplementIntakeUpdate,
    db: DbSession,
    _api_key: ApiKeyDep,
):
    existing = supplement_intake_service.get(db, intake_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Intake not found for this user")
    return supplement_intake_service.update(db, intake_id, payload, raise_404=True)


@router.delete(
    "/users/{user_id}/supplement-intakes/{intake_id}",
    response_model=SupplementIntakeResponse,
)
def delete_intake(user_id: UUID, intake_id: UUID, db: DbSession, _api_key: ApiKeyDep):
    existing = supplement_intake_service.get(db, intake_id, raise_404=True)
    if existing.user_id != user_id:
        raise HTTPException(status_code=404, detail="Intake not found for this user")
    return supplement_intake_service.delete(db, intake_id, raise_404=True)
