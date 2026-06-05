"""cardio_session table

Revision ID: c33dab88a227
Revises: 6710ba36438b

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c33dab88a227"
down_revision: Union[str, None] = "6710ba36438b"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "cardio_session",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=100), nullable=False),
        sa.Column("performed_at", sa.DateTime(), nullable=False),
        sa.Column("duration_min", sa.Numeric(precision=6, scale=1), nullable=False),
        sa.Column("avg_hr", sa.Integer(), nullable=True),
        sa.Column("distance_km", sa.Numeric(precision=6, scale=2), nullable=True),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_cardio_session_user_performed", "cardio_session", ["user_id", "performed_at"])


def downgrade() -> None:
    op.drop_index("ix_cardio_session_user_performed", table_name="cardio_session")
    op.drop_table("cardio_session")
