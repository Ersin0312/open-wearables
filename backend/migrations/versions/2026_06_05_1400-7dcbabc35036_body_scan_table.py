"""body_scan table (Renpho full measurements)

Revision ID: 7dcbabc35036
Revises: 425fb9be8c0c

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "7dcbabc35036"
down_revision: Union[str, None] = "425fb9be8c0c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "body_scan",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("measured_at", sa.DateTime(), nullable=False),
        sa.Column("source", sa.String(length=100), nullable=False),
        sa.Column("weight_kg", sa.Numeric(precision=6, scale=2), nullable=True),
        sa.Column("bmi", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("body_fat_percent", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("muscle_mass_kg", sa.Numeric(precision=6, scale=2), nullable=True),
        sa.Column("body_water_percent", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("bone_mass_kg", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("bmr_kcal", sa.Numeric(precision=7, scale=1), nullable=True),
        sa.Column("visceral_fat", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("subcutaneous_fat_percent", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("protein_percent", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_body_scan_user_measured", "body_scan", ["user_id", "measured_at"])


def downgrade() -> None:
    op.drop_index("ix_body_scan_user_measured", table_name="body_scan")
    op.drop_table("body_scan")
