from uuid import UUID

from sqlalchemy import or_
from sqlalchemy.orm import Query

from app.database import DbSession
from app.models import Supplement
from app.repositories.repositories import CrudRepository
from app.schemas.model_crud.supplements import SupplementCreate, SupplementUpdate


class SupplementRepository(CrudRepository[Supplement, SupplementCreate, SupplementUpdate]):
    def __init__(self, model: type[Supplement] = Supplement):
        super().__init__(model)

    def list_visible_for_user(
        self,
        db_session: DbSession,
        user_id: UUID,
        category: str | None = None,
        search: str | None = None,
    ) -> list[Supplement]:
        query: Query = db_session.query(self.model).filter(
            or_(
                self.model.is_seeded == True,  # noqa: E712
                self.model.created_by_user_id == user_id,
            )
        )

        if category:
            query = query.filter(self.model.category == category)
        if search:
            query = query.filter(self.model.name.ilike(f"%{search}%"))

        return query.order_by(self.model.is_seeded.desc(), self.model.name.asc()).all()
