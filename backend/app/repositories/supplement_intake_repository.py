from datetime import datetime
from uuid import UUID

from sqlalchemy.orm import Query

from app.database import DbSession
from app.models import SupplementIntake
from app.repositories.repositories import CrudRepository
from app.schemas.model_crud.supplements import (
    SupplementIntakeCreate,
    SupplementIntakeUpdate,
)


class SupplementIntakeRepository(
    CrudRepository[SupplementIntake, SupplementIntakeCreate, SupplementIntakeUpdate],
):
    def __init__(self, model: type[SupplementIntake] = SupplementIntake):
        super().__init__(model)

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
        query: Query = db_session.query(self.model).filter(self.model.user_id == user_id)

        if start_date:
            query = query.filter(self.model.taken_at >= start_date)
        if end_date:
            query = query.filter(self.model.taken_at < end_date)
        if supplement_id:
            query = query.filter(self.model.supplement_id == supplement_id)

        return query.order_by(self.model.taken_at.desc()).offset(offset).limit(limit).all()
