"""exercise image_url column

Revision ID: c4545b78d9b8
Revises: dd09ec21b4f4

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c4545b78d9b8"
down_revision: Union[str, None] = "dd09ec21b4f4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("exercise", sa.Column("image_url", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("exercise", "image_url")
