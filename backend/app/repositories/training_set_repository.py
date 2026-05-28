from uuid import UUID

from app.database import DbSession
from app.models import TrainingSet
from app.repositories.repositories import CrudRepository
from app.schemas.model_crud.training import TrainingSetCreate, TrainingSetUpdate


class TrainingSetRepository(
    CrudRepository[TrainingSet, TrainingSetCreate, TrainingSetUpdate],
):
    def __init__(self, model: type[TrainingSet] = TrainingSet):
        super().__init__(model)

    def list_for_session(self, db_session: DbSession, session_id: UUID) -> list[TrainingSet]:
        return (
            db_session.query(self.model)
            .filter(self.model.session_id == session_id)
            .order_by(self.model.created_at.asc())
            .all()
        )

    def get_last_for_session_and_exercise(
        self,
        db_session: DbSession,
        session_id: UUID,
        exercise_id: UUID,
    ) -> TrainingSet | None:
        """Used to compute the next set_number when adding a set inline."""
        return (
            db_session.query(self.model)
            .filter(
                self.model.session_id == session_id,
                self.model.exercise_id == exercise_id,
            )
            .order_by(self.model.set_number.desc())
            .first()
        )
