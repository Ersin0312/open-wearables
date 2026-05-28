from datetime import datetime, timezone
from logging import Logger, getLogger
from uuid import UUID

from app.database import DbSession
from app.models import Exercise, TrainingSession, TrainingSet
from app.repositories.exercise_repository import ExerciseRepository
from app.repositories.training_session_repository import TrainingSessionRepository
from app.repositories.training_set_repository import TrainingSetRepository
from app.schemas.model_crud.training import (
    ExerciseCreate,
    ExerciseUpdate,
    TrainingSessionCreate,
    TrainingSessionUpdate,
    TrainingSetCreate,
    TrainingSetUpdate,
)
from app.services.services import AppService
from app.utils.exceptions import ResourceNotFoundError


class ExerciseService(AppService[ExerciseRepository, Exercise, ExerciseCreate, ExerciseUpdate]):
    def __init__(self, log: Logger, **kwargs):
        super().__init__(crud_model=ExerciseRepository, model=Exercise, log=log, **kwargs)

    def list_visible_for_user(
        self,
        db_session: DbSession,
        user_id: UUID,
        split_tag: str | None = None,
        muscle_group: str | None = None,
        search: str | None = None,
    ) -> list[Exercise]:
        return self.crud.list_visible_for_user(db_session, user_id, split_tag, muscle_group, search)


class TrainingSessionService(
    AppService[TrainingSessionRepository, TrainingSession, TrainingSessionCreate, TrainingSessionUpdate],
):
    def __init__(self, log: Logger, **kwargs):
        super().__init__(
            crud_model=TrainingSessionRepository,
            model=TrainingSession,
            log=log,
            **kwargs,
        )

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
        return self.crud.list_for_user(db_session, user_id, start_date, end_date, split_tag, limit, offset)

    def get_with_sets(self, db_session: DbSession, session_id: UUID) -> TrainingSession:
        session = self.crud.get_with_sets(db_session, session_id)
        if not session:
            raise ResourceNotFoundError("training_session", session_id)
        return session

    def end_session(self, db_session: DbSession, session_id: UUID, ended_at: datetime | None = None) -> TrainingSession:
        session = self.get_with_sets(db_session, session_id)
        session.ended_at = ended_at or datetime.now(timezone.utc)
        db_session.add(session)
        db_session.commit()
        db_session.refresh(session)
        self.logger.debug(f"Ended training session {session_id}")
        return session

    def get_last_for_user_and_split(
        self,
        db_session: DbSession,
        user_id: UUID,
        split_tag: str,
    ) -> TrainingSession | None:
        return self.crud.get_last_for_user_and_split(db_session, user_id, split_tag)


class TrainingSetService(AppService[TrainingSetRepository, TrainingSet, TrainingSetCreate, TrainingSetUpdate]):
    def __init__(self, log: Logger, **kwargs):
        super().__init__(crud_model=TrainingSetRepository, model=TrainingSet, log=log, **kwargs)

    def add_set(
        self,
        db_session: DbSession,
        session_id: UUID,
        payload: TrainingSetCreate,
    ) -> TrainingSet:
        """Create a set linked to the given session. Auto-fills set_number when 0 or missing."""
        # Persist via raw model to bind session_id (which isn't on TrainingSetCreate)
        data = payload.model_dump()
        data["session_id"] = session_id
        creation = TrainingSet(**data)
        db_session.add(creation)
        db_session.commit()
        db_session.refresh(creation)
        self.logger.debug(f"Logged set {creation.id} in session {session_id}")
        return creation

    def list_for_session(self, db_session: DbSession, session_id: UUID) -> list[TrainingSet]:
        return self.crud.list_for_session(db_session, session_id)


# Singletons
exercise_service = ExerciseService(log=getLogger(__name__))
training_session_service = TrainingSessionService(log=getLogger(__name__))
training_set_service = TrainingSetService(log=getLogger(__name__))
