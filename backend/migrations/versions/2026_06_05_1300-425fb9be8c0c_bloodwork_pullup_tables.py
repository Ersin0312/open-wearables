"""bloodwork_entry + pullup_entry tables

Revision ID: 425fb9be8c0c
Revises: c33dab88a227

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "425fb9be8c0c"
down_revision: Union[str, None] = "c33dab88a227"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "bloodwork_entry",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("marker", sa.String(length=100), nullable=False),
        sa.Column("value", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("unit", sa.String(length=100), nullable=False),
        sa.Column("taken_at", sa.DateTime(), nullable=False),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_bloodwork_entry_user_taken", "bloodwork_entry", ["user_id", "taken_at"])

    op.create_table(
        "pullup_entry",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("reps", sa.Integer(), nullable=False),
        sa.Column("added_weight_kg", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("performed_at", sa.DateTime(), nullable=False),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_pullup_entry_user_performed", "pullup_entry", ["user_id", "performed_at"])


def downgrade() -> None:
    op.drop_index("ix_pullup_entry_user_performed", table_name="pullup_entry")
    op.drop_table("pullup_entry")
    op.drop_index("ix_bloodwork_entry_user_taken", table_name="bloodwork_entry")
    op.drop_table("bloodwork_entry")
