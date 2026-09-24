import uuid

from sqlalchemy import CheckConstraint, ForeignKey, Integer, String, Uuid, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, IdMixin, TimestampMixin


class User(IdMixin, TimestampMixin, Base):
    """Account credentials only. Everything personal lives in Profile or feature tables."""

    __tablename__ = "users"

    email: Mapped[str] = mapped_column(String(254), unique=True, index=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    # Bumped on password change / "sign out everywhere"; tokens carry it, so old ones stop working.
    token_version: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default=text("0"))

    profile: Mapped["Profile"] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan", lazy="joined"
    )


class Profile(TimestampMixin, Base):
    """Private preferences and daily goals. Never shared with other users."""

    __tablename__ = "profiles"
    __table_args__ = (
        CheckConstraint("daily_study_goal_minutes BETWEEN 0 AND 960", name="study_goal_range"),
        CheckConstraint("daily_step_goal BETWEEN 0 AND 100000", name="step_goal_range"),
        CheckConstraint("daily_task_goal BETWEEN 0 AND 50", name="task_goal_range"),
        CheckConstraint("preferred_workout_time IN ('morning', 'afternoon', 'evening')", name="workout_time"),
        CheckConstraint("daily_sleep_goal_minutes BETWEEN 0 AND 960", name="sleep_goal_range"),
        CheckConstraint("daily_calorie_goal BETWEEN 0 AND 10000", name="calorie_goal_range"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    display_name: Mapped[str] = mapped_column(String(60), nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="UTC")
    daily_study_goal_minutes: Mapped[int] = mapped_column(Integer, nullable=False, default=240)
    daily_step_goal: Mapped[int] = mapped_column(Integer, nullable=False, default=8000)
    daily_task_goal: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    preferred_workout_time: Mapped[str] = mapped_column(String(16), nullable=False, default="evening")
    daily_sleep_goal_minutes: Mapped[int] = mapped_column(
        Integer, nullable=False, default=480, server_default=text("480")
    )
    daily_calorie_goal: Mapped[int] = mapped_column(Integer, nullable=False, default=2000, server_default=text("2000"))
    # Public handle for friend requests (Phase 3). Optional until the user sets one.
    username: Mapped[str | None] = mapped_column(String(30), unique=True, index=True)

    user: Mapped[User] = relationship(back_populates="profile")
