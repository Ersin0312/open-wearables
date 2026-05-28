from datetime import datetime
from uuid import UUID

from sqlalchemy.orm import Query, selectinload

from app.database import DbSession
from app.models import TrainingSession
from app.repositories.repositories import CrudRepository
from app.schemas.model_crud.training import TrainingSessionCreate, TrainingSessionUpdate


class TrainingSessionRepository(
    CrudRepository[TrainingSession, TrainingSessionCreate, TrainingSessionUpdate],
):
    def __init__(self, model: type[TrainingSession] = TrainingSession):
        super().__init__(model)

    def list_for_user(
        self,
        db_session: DbSession,
        user_id: UUID,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
        split_tag: str | None = None,
        limit: int = 50,
        offset: int = 0,
    ) -> list[TrainingSession]:
        query: Query = (
            db_session.query(self.model)
            .filter(self.model.user_id == user_id)
            .options(selectinload(self.model.sets))
        )

        if start_date:
            query = query.filter(self.model.started_at >= start_date)
        if end_date:
            query = query.filter(self.model.started_at < end_date)
        if split_tag:
            query = query.filter(self.model.split_tag == split_tag)

        return query.order_by(self.model.started_at.desc()).offset(offset).limit(limit).all()

    def get_with_sets(self, db_session: DbSession, session_id: UUID) -> TrainingSession | None:
        return (
            db_session.query(self.model)
            .options(selectinload(self.model.sets))
            .filter(self.model.id == session_id)
            .one_or_none()
        )

    def get_last_for_user_and_split(
        self,
        db_session: DbSession,
        user_id: UUID,
        split_tag: str,
    ) -> TrainingSession | None:
        """Used for the 'repeat last session' shortcut."""
        return (
            db_session.query(self.model)
            .options(selectinload(self.model.sets))
            .filter(self.model.user_id == user_id, self.model.split_tag == split_tag)
            .order_by(self.model.started_at.desc())
            .first()
        )
