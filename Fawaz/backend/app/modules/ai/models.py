import uuid
from datetime import date

from sqlalchemy import JSON, Boolean, Date, ForeignKey, Index, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin


class AIPlan(IdMixin, TimestampMixin, Base):
    """A generated daily plan. History is kept so later phases can learn what was missed."""

    __tablename__ = "ai_plans"
    __table_args__ = (Index("ix_ai_plans_user_date", "user_id", "plan_date"),)

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    plan_date: Mapped[date] = mapped_column(Date, nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    fallback_reason: Mapped[str | None] = mapped_column(String(40))
    is_fallback: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    content: Mapped[dict] = mapped_column(JSON, nullable=False)
