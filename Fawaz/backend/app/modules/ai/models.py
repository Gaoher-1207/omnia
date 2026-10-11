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


class PlanItemOutcome(IdMixin, TimestampMixin, Base):
    """What actually happened to one plan block, recorded by its owner.

    Keyed by the block's stable `item_key`, which survives plan revisions, so an
    outcome stays attached when a replan moves the block. Title and times are
    snapshotted so the history survives even if a later revision drops the block.
    """

    __tablename__ = "plan_item_outcomes"
    __table_args__ = (
        CheckConstraint("status IN ('done', 'partial', 'skipped')", name="status"),
        Index("uq_plan_item_outcomes_owner_item", "user_id", "plan_date", "item_key", unique=True),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    plan_date: Mapped[date] = mapped_column(Date, nullable=False)
    item_key: Mapped[str] = mapped_column(String(80), nullable=False)
    # The revision the outcome was recorded against (for audit; the key is what matters).
    plan_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("ai_plans.id", ondelete="SET NULL"))
    status: Mapped[str] = mapped_column(String(10), nullable=False)
    category: Mapped[str] = mapped_column(String(12), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    start: Mapped[str] = mapped_column(String(5), nullable=False)
    end: Mapped[str] = mapped_column(String(5), nullable=False)
    task_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    subject_id: Mapped[uuid.UUID | None] = mapped_column(Uuid)
    recorded_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False)
    # Minutes actually done, for a partly done block (null when not given).
    minutes: Mapped[int | None] = mapped_column(Integer)
    # The study session credited for a study block, if any (see study_credit.py).
    study_session_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("study_sessions.id", ondelete="SET NULL")
    )
