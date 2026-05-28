from uuid import UUID

from sqlalchemy import or_
from sqlalchemy.orm import Query

from app.database import DbSession
from app.models import Exercise
from app.repositories.repositories import CrudRepository
from app.schemas.model_crud.training import ExerciseCreate, ExerciseUpdate


class ExerciseRepository(CrudRepository[Exercise, ExerciseCreate, ExerciseUpdate]):
    def __init__(self, model: type[Exercise] = Exercise):
        super().__init__(model)

    def list_visible_for_user(
        self,
        db_session: DbSession,
        user_id: UUID,
        split_tag: str | None = None,
        muscle_group: str | None = None,
        search: str | None = None,
    ) -> list[Exercise]:
        """Return seeded library entries plus the user's own custom exercises.

        Optional filters: split_tag (push/pull/legs/core), muscle_group, fuzzy name search.
        """
        query: Query = db_session.query(self.model).filter(
            or_(
                self.model.is_seeded == True,  # noqa: E712
                self.model.created_by_user_id == user_id,
            )
        )

        if split_tag:
            query = query.filter(self.model.default_split_tag == split_tag)
        if muscle_group:
            query = query.filter(self.model.primary_muscle_group == muscle_group)
        if search:
            query = query.filter(self.model.name.ilike(f"%{search}%"))

        return query.order_by(self.model.is_seeded.desc(), self.model.name.asc()).all()

    def get_by_name(self, db_session: DbSession, name: str) -> Exercise | None:
        return db_session.query(self.model).filter(self.model.name == name).one_or_none()
