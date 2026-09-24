import uuid
from datetime import date

from sqlalchemy import Boolean, CheckConstraint, Date, ForeignKey, Integer, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin


class ActivityDay(IdMixin, TimestampMixin, Base):
    """One row per user per local day: steps and whether a workout happened."""

    __tablename__ = "activity_days"
    __table_args__ = (
        UniqueConstraint("user_id", "day", name="uq_activity_days_user_day"),
        CheckConstraint("steps BETWEEN 0 AND 200000", name="steps_range"),
        CheckConstraint("workout_minutes BETWEEN 0 AND 600", name="workout_minutes_range"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    day: Mapped[date] = mapped_column(Date, nullable=False)
    steps: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    workout_done: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    workout_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    workout_type: Mapped[str | None] = mapped_column(String(40))
