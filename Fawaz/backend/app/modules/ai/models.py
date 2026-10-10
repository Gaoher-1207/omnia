import uuid
from datetime import date, datetime

from sqlalchemy import JSON, Boolean, CheckConstraint, Date, ForeignKey, Index, Integer, String, Uuid, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin
from app.db.types import UTCDateTime


class AIPlan(IdMixin, TimestampMixin, Base):
    """A generated daily plan. History is kept so later phases can learn what was missed."""

    __tablename__ = "ai_plans"
    __table_args__ = (
        Index("ix_ai_plans_user_date", "user_id", "plan_date"),
        Index("uq_ai_plans_user_date_revision", "user_id", "plan_date", "revision", unique=True),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    plan_date: Mapped[date] = mapped_column(Date, nullable=False)
    revision: Mapped[int] = mapped_column(Integer, nullable=False, default=1, server_default=text("1"))
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    fallback_reason: Mapped[str | None] = mapped_column(String(40))
    is_fallback: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    content: Mapped[dict] = mapped_column(JSON, nullable=False)


class ReplanProposal(IdMixin, TimestampMixin, Base):
    __tablename__ = "replan_proposals"
    __table_args__ = (
        CheckConstraint("status IN ('pending', 'applied', 'dismissed', 'stale', 'expired', 'invalid')", name="status"),
        Index("ix_replan_proposals_owner_status", "user_id", "status"),
        Index("ix_replan_proposals_base_plan", "base_plan_id"),
        Index("ix_replan_proposals_owner_date", "user_id", "plan_date", "created_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    base_plan_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("ai_plans.id", ondelete="CASCADE"), nullable=False)
    base_revision: Mapped[int] = mapped_column(Integer, nullable=False)
    base_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    plan_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(12), nullable=False, default="pending", server_default="pending")
    provider: Mapped[str] = mapped_column(String(20), nullable=False)
    request: Mapped[str] = mapped_column(String(1000), nullable=False)
    summary: Mapped[str] = mapped_column(String(280), nullable=False)
    explanation: Mapped[str] = mapped_column(String(1000), nullable=False)
    operations: Mapped[list] = mapped_column(JSON, nullable=False)
    schedule: Mapped[list] = mapped_column(JSON, nullable=False)
    warnings: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    validation: Mapped[dict] = mapped_column(JSON, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    applied_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    dismissed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
