from uuid import UUID

from sqlalchemy.orm import selectinload

from app.database import DbSession
from app.models import SupplementStack
from app.repositories.repositories import CrudRepository
from app.schemas.model_crud.supplements import SupplementStackCreate, SupplementStackUpdate


class SupplementStackRepository(
    CrudRepository[SupplementStack, SupplementStackCreate, SupplementStackUpdate],
):
    def __init__(self, model: type[SupplementStack] = SupplementStack):
        super().__init__(model)

    def list_for_user(self, db_session: DbSession, user_id: UUID) -> list[SupplementStack]:
        return (
            db_session.query(self.model)
            .options(selectinload(self.model.items))
            .filter(self.model.user_id == user_id)
            .order_by(self.model.created_at.desc())
            .all()
        )

    def get_with_items(self, db_session: DbSession, stack_id: UUID) -> SupplementStack | None:
        return (
            db_session.query(self.model)
            .options(selectinload(self.model.items))
            .filter(self.model.id == stack_id)
            .one_or_none()
        )
