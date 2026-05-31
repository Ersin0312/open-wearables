from decimal import Decimal
from uuid import UUID

from sqlalchemy import ForeignKey, Numeric
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import BaseDbModel
from app.mappings import ManyToOne, PrimaryKey, str_32


class SupplementStackItem(BaseDbModel):
    """An item within a SupplementStack — supplement + dose override."""

    __tablename__ = "supplement_stack_item"

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    stack_id: Mapped[UUID] = mapped_column(
        ForeignKey("supplement_stack.id", ondelete="CASCADE"),
    )
    supplement_id: Mapped[UUID] = mapped_column(
        ForeignKey("supplement.id", ondelete="RESTRICT"),
    )

    order_index: Mapped[int] = mapped_column(default=0)
    # Optional overrides — fall back to supplement.default_* when null
    dose: Mapped[Decimal | None] = mapped_column(Numeric(10, 2), nullable=True)
    unit: Mapped[str_32 | None] = mapped_column(nullable=True)

    stack: Mapped[ManyToOne["SupplementStack"]] = relationship(
        "SupplementStack",
        back_populates="items",
    )
