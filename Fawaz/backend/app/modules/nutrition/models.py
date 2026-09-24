import uuid
from datetime import date

from sqlalchemy import CheckConstraint, Date, ForeignKey, Index, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, IdMixin, TimestampMixin


class Meal(IdMixin, TimestampMixin, Base):
    """A meal the user logged. Photos are never stored: only the numbers the user confirmed."""

    __tablename__ = "meals"
    __table_args__ = (
        CheckConstraint("meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')", name="meal_type"),
        CheckConstraint("source IN ('manual', 'photo_estimate')", name="source"),
        CheckConstraint("calories BETWEEN 0 AND 5000", name="calories_range"),
        CheckConstraint("protein_g BETWEEN 0 AND 500", name="protein_range"),
        CheckConstraint("carbs_g BETWEEN 0 AND 1000", name="carbs_range"),
        CheckConstraint("fat_g BETWEEN 0 AND 500", name="fat_range"),
        Index("ix_meals_user_day", "user_id", "day"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    day: Mapped[date] = mapped_column(Date, nullable=False)
    meal_type: Mapped[str] = mapped_column(String(10), nullable=False)
    description: Mapped[str] = mapped_column(String(200), nullable=False)
    calories: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    protein_g: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    carbs_g: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    fat_g: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="manual")
