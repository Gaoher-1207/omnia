import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, CheckConstraint, Date, Float, ForeignKey, Index, String, Uuid, false
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin
from app.db.types import UTCDateTime

GOAL_CATEGORIES = ("study", "tasks", "activity", "sleep", "nutrition", "habits")


class Goal(IdMixin, TimestampMixin, Base):
    """A long-term goal: measurable (current of target unit) or completion-only.

    Not the profile's daily targets. Progress is derived from the values, and
    completion is always the user's explicit decision.
    """

    __tablename__ = "goals"
    __table_args__ = (
        CheckConstraint("category IN ('study', 'tasks', 'activity', 'sleep', 'nutrition', 'habits')", name="category"),
        CheckConstraint(
            "(target_value IS NULL AND current_value IS NULL AND unit IS NULL) OR "
            "(target_value > 0 AND current_value >= 0 AND unit IS NOT NULL)",
            name="measurement",
        ),
        Index("ix_goals_user_completed", "user_id", "completed"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    description: Mapped[str | None] = mapped_column(String(500))
    category: Mapped[str] = mapped_column(String(12), nullable=False)
    target_value: Mapped[float | None] = mapped_column(Float)
    current_value: Mapped[float | None] = mapped_column(Float)
    unit: Mapped[str | None] = mapped_column(String(24))
    deadline: Mapped[date | None] = mapped_column(Date)
    completed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default=false())
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
