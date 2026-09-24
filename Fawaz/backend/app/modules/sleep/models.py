import uuid
from datetime import date, time

from sqlalchemy import CheckConstraint, Date, ForeignKey, Integer, Time, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin


class SleepLog(IdMixin, TimestampMixin, Base):
    """One night of sleep, filed under the local date the user woke up."""

    __tablename__ = "sleep_logs"
    __table_args__ = (
        UniqueConstraint("user_id", "day", name="uq_sleep_logs_user_day"),
        CheckConstraint("duration_minutes BETWEEN 0 AND 1440", name="duration_range"),
        CheckConstraint("quality BETWEEN 1 AND 5", name="quality_range"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    day: Mapped[date] = mapped_column(Date, nullable=False)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    quality: Mapped[int | None] = mapped_column(Integer)
    bedtime: Mapped[time | None] = mapped_column(Time)
    wake_time: Mapped[time | None] = mapped_column(Time)
