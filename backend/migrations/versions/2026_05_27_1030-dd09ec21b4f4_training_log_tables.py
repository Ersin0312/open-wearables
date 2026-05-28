"""training log tables

Revision ID: dd09ec21b4f4
Revises: 6b11080054a0

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "dd09ec21b4f4"
down_revision: Union[str, None] = "6b11080054a0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "exercise",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("equipment", sa.String(50), nullable=False),
        sa.Column("primary_muscle_group", sa.String(32), nullable=False),
        sa.Column("default_split_tag", sa.String(32), nullable=False),
        sa.Column("is_seeded", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("created_by_user_id", sa.UUID(), nullable=True),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_exercise_split_tag", "exercise", ["default_split_tag"])
    op.create_index("ix_exercise_muscle_group", "exercise", ["primary_muscle_group"])
    op.create_index("ix_exercise_created_by_user", "exercise", ["created_by_user_id"])

    op.create_table(
        "training_session",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("split_tag", sa.String(32), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_training_session_user_started", "training_session", ["user_id", "started_at"])

    op.create_table(
        "training_set",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("session_id", sa.UUID(), nullable=False),
        sa.Column("exercise_id", sa.UUID(), nullable=False),
        sa.Column("set_number", sa.Integer(), nullable=False),
        sa.Column("reps", sa.Integer(), nullable=False),
        sa.Column("weight_kg", sa.Numeric(5, 2), nullable=False),
        sa.Column("rpe", sa.Numeric(5, 2), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["session_id"], ["training_session.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["exercise_id"], ["exercise.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_training_set_session", "training_set", ["session_id"])
    op.create_index("ix_training_set_exercise_created", "training_set", ["exercise_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_training_set_exercise_created", table_name="training_set")
    op.drop_index("ix_training_set_session", table_name="training_set")
    op.drop_table("training_set")

    op.drop_index("ix_training_session_user_started", table_name="training_session")
    op.drop_table("training_session")

    op.drop_index("ix_exercise_created_by_user", table_name="exercise")
    op.drop_index("ix_exercise_muscle_group", table_name="exercise")
    op.drop_index("ix_exercise_split_tag", table_name="exercise")
    op.drop_table("exercise")
