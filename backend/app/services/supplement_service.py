from datetime import datetime, timezone
from logging import Logger, getLogger
from uuid import UUID, uuid4

from app.database import DbSession
from app.models import (
    Supplement,
    SupplementIntake,
    SupplementStack,
    SupplementStackItem,
)
from app.repositories.supplement_intake_repository import SupplementIntakeRepository
from app.repositories.supplement_repository import SupplementRepository
from app.repositories.supplement_stack_repository import SupplementStackRepository
from app.schemas.model_crud.supplements import (
    SupplementCreate,
    SupplementIntakeCreate,
    SupplementIntakeUpdate,
    SupplementStackCreate,
    SupplementStackItemCreate,
    SupplementStackUpdate,
    SupplementUpdate,
)
from app.services.services import AppService
from app.utils.exceptions import ResourceNotFoundError


class SupplementService(
    AppService[SupplementRepository, Supplement, SupplementCreate, SupplementUpdate],
):
    def __init__(self, log: Logger, **kwargs):
        super().__init__(crud_model=SupplementRepository, model=Supplement, log=log, **kwargs)

    def list_visible_for_user(
        self,
        db_session: DbSession,
        user_id: UUID,
        category: str | None = None,
        search: str | None = None,
    ) -> list[Supplement]:
        return self.crud.list_visible_for_user(db_session, user_id, category, search)


class SupplementStackService(
    AppService[
        SupplementStackRepository,
        SupplementStack,
        SupplementStackCreate,
        SupplementStackUpdate,
    ],
):
    def __init__(self, log: Logger, **kwargs):
        super().__init__(
            crud_model=SupplementStackRepository,
            model=SupplementStack,
            log=log,
            **kwargs,
        )

    def list_for_user(self, db_session: DbSession, user_id: UUID) -> list[SupplementStack]:
        return self.crud.list_for_user(db_session, user_id)

    def get_with_items(self, db_session: DbSession, stack_id: UUID) -> SupplementStack:
        stack = self.crud.get_with_items(db_session, stack_id)
        if not stack:
            raise ResourceNotFoundError("supplement_stack", stack_id)
        return stack

    def create_with_items(
        self,
        db_session: DbSession,
        user_id: UUID,
        payload: SupplementStackCreate,
    ) -> SupplementStack:
        """Create a stack and its items in a single transaction."""
        stack = SupplementStack(
            id=payload.id,
            user_id=user_id,
            name=payload.name,
            notes=payload.notes,
        )
        db_session.add(stack)
        db_session.flush()

        for item_payload in payload.items:
            db_session.add(
                SupplementStackItem(
                    id=uuid4(),
                    stack_id=stack.id,
                    supplement_id=item_payload.supplement_id,
                    order_index=item_payload.order_index,
                    dose=item_payload.dose,
                    unit=item_payload.unit,
                )
            )
        db_session.commit()
        return self.get_with_items(db_session, stack.id)

    def update_with_items(
        self,
        db_session: DbSession,
        stack_id: UUID,
        payload: SupplementStackUpdate,
    ) -> SupplementStack:
        """Update stack name/notes and (if items provided) REPLACE its items."""
        stack = self.get_with_items(db_session, stack_id)
        if payload.name is not None:
            stack.name = payload.name
        if payload.notes is not None:
            stack.notes = payload.notes

        if payload.items is not None:
            # Replace all items: cascade-delete then re-add
            for old_item in list(stack.items):
                db_session.delete(old_item)
            db_session.flush()
            for item_payload in payload.items:
                db_session.add(
                    SupplementStackItem(
                        id=uuid4(),
                        stack_id=stack.id,
                        supplement_id=item_payload.supplement_id,
                        order_index=item_payload.order_index,
                        dose=item_payload.dose,
                        unit=item_payload.unit,
                    )
                )

        db_session.commit()
        return self.get_with_items(db_session, stack_id)

    def log_stack_now(
        self,
        db_session: DbSession,
        stack_id: UUID,
        user_id: UUID,
        when: datetime | None = None,
    ) -> list[SupplementIntake]:
        """Bulk-create intakes for every item in a stack, all timestamped to `when`
        (defaults to now). Each item uses its own dose/unit override or falls back
        to the supplement's default."""
        stack = self.get_with_items(db_session, stack_id)
        ts = when or datetime.now(timezone.utc)
        intakes: list[SupplementIntake] = []
        for item in stack.items:
            supplement = db_session.get(Supplement, item.supplement_id)
            if supplement is None:
                continue
            intake = SupplementIntake(
                id=uuid4(),
                user_id=user_id,
                supplement_id=supplement.id,
                stack_id=stack.id,
                taken_at=ts,
                dose=item.dose if item.dose is not None else (supplement.default_dose or 0),
                unit=item.unit if item.unit else supplement.default_unit,
            )
            db_session.add(intake)
            intakes.append(intake)
        db_session.commit()
        for i in intakes:
            db_session.refresh(i)
        self.logger.debug(f"Logged stack {stack_id} ({len(intakes)} intakes) for user {user_id}")
        return intakes


class SupplementIntakeService(
    AppService[
        SupplementIntakeRepository,
        SupplementIntake,
        SupplementIntakeCreate,
        SupplementIntakeUpdate,
    ],
):
    def __init__(self, log: Logger, **kwargs):
        super().__init__(
            crud_model=SupplementIntakeRepository,
            model=SupplementIntake,
            log=log,
            **kwargs,
        )

    def add_intake(
        self,
        db_session: DbSession,
        user_id: UUID,
        payload: SupplementIntakeCreate,
    ) -> SupplementIntake:
        data = payload.model_dump()
        data["user_id"] = user_id
        intake = SupplementIntake(**data)
        db_session.add(intake)
        db_session.commit()
        db_session.refresh(intake)
        return intake

    def list_for_user(
        self,
        db_session: DbSession,
        user_id: UUID,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
        supplement_id: UUID | None = None,
        limit: int = 100,
        offset: int = 0,
    ) -> list[SupplementIntake]:
        return self.crud.list_for_user(db_session, user_id, start_date, end_date, supplement_id, limit, offset)


# Singletons
supplement_service = SupplementService(log=getLogger(__name__))
supplement_stack_service = SupplementStackService(log=getLogger(__name__))
supplement_intake_service = SupplementIntakeService(log=getLogger(__name__))
