import uuid
from datetime import date, datetime, time

from sqlalchemy import CheckConstraint, Date, ForeignKey, Index, Integer, String, Text, Time, Uuid, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin
from app.db.types import UTCDateTime

TASK_PRIORITIES = ("low", "medium", "high")
TASK_STATUSES = ("todo", "done")
TASK_CATEGORIES = ("study", "tasks", "activity", "sleep", "nutrition", "habits")


class Task(IdMixin, TimestampMixin, Base):
    __tablename__ = "tasks"
    __table_args__ = (
        CheckConstraint("priority IN ('low', 'medium', 'high')", name="priority"),
        CheckConstraint("status IN ('todo', 'done')", name="status"),
        CheckConstraint("category IN ('study', 'tasks', 'activity', 'sleep', 'nutrition', 'habits')", name="category"),
        CheckConstraint("estimated_minutes BETWEEN 1 AND 1440", name="estimate_range"),
        Index("ix_tasks_user_status_due", "user_id", "status", "due_date"),
        Index("ix_tasks_user_completed_at", "user_id", "completed_at"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)
    priority: Mapped[str] = mapped_column(String(8), nullable=False, default="medium")
    status: Mapped[str] = mapped_column(String(8), nullable=False, default="todo")
    due_date: Mapped[date | None] = mapped_column(Date)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)
    # Optional local time on the due date (the Flutter app lets users pick one).
    due_time: Mapped[time | None] = mapped_column(Time)
    estimated_minutes: Mapped[int | None] = mapped_column(Integer)
    category: Mapped[str] = mapped_column(String(12), nullable=False, default="tasks", server_default=text("'tasks'"))
