from uuid import UUID

from sqlalchemy import Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import BaseDbModel
from app.mappings import FKUser, OneToMany, PrimaryKey, str_100


class SupplementStack(BaseDbModel):
    """A named bundle of supplements a user takes together (e.g. 'Morning Stack')."""

    __tablename__ = "supplement_stack"
    __table_args__ = (
        Index("ix_supplement_stack_user", "user_id"),
    )

    id: Mapped[PrimaryKey[UUID]] = mapped_column()
    user_id: Mapped[FKUser]
    name: Mapped[str_100]
    notes: Mapped[str | None] = mapped_column(nullable=True)

    items: Mapped[OneToMany["SupplementStackItem"]] = relationship(
        "SupplementStackItem",
        back_populates="stack",
        cascade="all, delete-orphan",
        order_by="SupplementStackItem.order_index",
    )
