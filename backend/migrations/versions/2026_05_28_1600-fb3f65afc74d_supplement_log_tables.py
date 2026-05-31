"""supplement log tables

Revision ID: fb3f65afc74d
Revises: c4545b78d9b8

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "fb3f65afc74d"
down_revision: Union[str, None] = "c4545b78d9b8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "supplement",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("category", sa.String(32), nullable=False),
        sa.Column("default_dose", sa.Numeric(10, 2), nullable=True),
        sa.Column("default_unit", sa.String(32), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("is_seeded", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("created_by_user_id", sa.UUID(), nullable=True),
        sa.ForeignKeyConstraint(["created_by_user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index("ix_supplement_category", "supplement", ["category"])
    op.create_index("ix_supplement_created_by_user", "supplement", ["created_by_user_id"])

    op.create_table(
        "supplement_stack",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(100), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_supplement_stack_user", "supplement_stack", ["user_id"])

    op.create_table(
        "supplement_stack_item",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("stack_id", sa.UUID(), nullable=False),
        sa.Column("supplement_id", sa.UUID(), nullable=False),
        sa.Column("order_index", sa.Integer(), server_default="0", nullable=False),
        sa.Column("dose", sa.Numeric(10, 2), nullable=True),
        sa.Column("unit", sa.String(32), nullable=True),
        sa.ForeignKeyConstraint(["stack_id"], ["supplement_stack.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["supplement_id"], ["supplement.id"], ondelete="RESTRICT"),
        sa.PrimaryKeyConstraint("id"),
    )

    op.create_table(
        "supplement_intake",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("supplement_id", sa.UUID(), nullable=False),
        sa.Column("stack_id", sa.UUID(), nullable=True),
        sa.Column("taken_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("dose", sa.Numeric(10, 2), nullable=False),
        sa.Column("unit", sa.String(32), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["user.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["supplement_id"], ["supplement.id"], ondelete="RESTRICT"),
        sa.ForeignKeyConstraint(["stack_id"], ["supplement_stack.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_supplement_intake_user_taken", "supplement_intake", ["user_id", "taken_at"])
    op.create_index("ix_supplement_intake_supplement", "supplement_intake", ["supplement_id"])


def downgrade() -> None:
    op.drop_index("ix_supplement_intake_supplement", table_name="supplement_intake")
    op.drop_index("ix_supplement_intake_user_taken", table_name="supplement_intake")
    op.drop_table("supplement_intake")

    op.drop_table("supplement_stack_item")

    op.drop_index("ix_supplement_stack_user", table_name="supplement_stack")
    op.drop_table("supplement_stack")

    op.drop_index("ix_supplement_created_by_user", table_name="supplement")
    op.drop_index("ix_supplement_category", table_name="supplement")
    op.drop_table("supplement")
