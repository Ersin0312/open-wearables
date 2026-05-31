"""supplement brand + recommended_daily_dose columns

Revision ID: 5fa0117029fc
Revises: fb3f65afc74d

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "5fa0117029fc"
down_revision: Union[str, None] = "fb3f65afc74d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("supplement", sa.Column("brand", sa.String(length=100), nullable=True))
    op.add_column(
        "supplement",
        sa.Column("recommended_daily_dose", sa.Numeric(precision=10, scale=2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("supplement", "recommended_daily_dose")
    op.drop_column("supplement", "brand")
