"""nutrition_entry table

Revision ID: 6710ba36438b
Revises: 5fa0117029fc

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "6710ba36438b"
down_revision: Union[str, None] = "5fa0117029fc"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "nutrition_entry",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("eaten_at", sa.DateTime(), nullable=False),
        sa.Column("quantity_g", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("calories", sa.Numeric(precision=10, scale=2), nullable=False),
        sa.Column("protein_g", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("carbs_g", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("fat_g", sa.Numeric(precision=10, scale=2), nullable=True),
        sa.Column("source", sa.String(), nullable=True),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_nutrition_entry_user_eaten", "nutrition_entry", ["user_id", "eaten_at"])


def downgrade() -> None:
    op.drop_index("ix_nutrition_entry_user_eaten", table_name="nutrition_entry")
    op.drop_table("nutrition_entry")
