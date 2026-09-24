import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, IdMixin, TimestampMixin
from app.db.types import UTCDateTime


class Subject(IdMixin, TimestampMixin, Base):
    __tablename__ = "subjects"
    __table_args__ = (UniqueConstraint("user_id", "name", name="uq_subjects_user_name"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(60), nullable=False)
    color: Mapped[str | None] = mapped_column(String(7))


class Exam(IdMixin, TimestampMixin, Base):
    __tablename__ = "exams"
    __table_args__ = (Index("ix_exams_user_date", "user_id", "exam_date"),)

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    exam_date: Mapped[date] = mapped_column(Date, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)

    subject: Mapped[Subject] = relationship(lazy="joined")


class BacklogItem(IdMixin, TimestampMixin, Base):
    """A topic still to cover: an arrear/backlog chapter or a revision item."""

    __tablename__ = "backlog_items"
    __table_args__ = (
        CheckConstraint("kind IN ('backlog', 'revision')", name="kind"),
        CheckConstraint("status IN ('pending', 'done')", name="status"),
        CheckConstraint("estimated_minutes BETWEEN 5 AND 600", name="estimate_range"),
        Index("ix_backlog_items_user_status", "user_id", "status"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    kind: Mapped[str] = mapped_column(String(10), nullable=False, default="backlog")
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="pending")
    estimated_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=60)
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime)

    subject: Mapped[Subject] = relationship(lazy="joined")


class StudySession(IdMixin, TimestampMixin, Base):
    __tablename__ = "study_sessions"
    __table_args__ = (
        CheckConstraint("duration_minutes BETWEEN 1 AND 720", name="duration_range"),
        Index("ix_study_sessions_user_date", "user_id", "session_date"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    subject_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("subjects.id", ondelete="SET NULL"), index=True
    )
    backlog_item_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid, ForeignKey("backlog_items.id", ondelete="SET NULL"), index=True
    )
    session_date: Mapped[date] = mapped_column(Date, nullable=False)
    duration_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    notes: Mapped[str | None] = mapped_column(Text)

    subject: Mapped[Subject | None] = relationship(lazy="joined")
