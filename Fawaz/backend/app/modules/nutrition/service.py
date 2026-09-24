import uuid
from collections import defaultdict
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.common.ownership import get_owned
from app.modules.nutrition.models import Meal
from app.modules.nutrition.schemas import DayTotals, MealUpdate, NutritionTotals


def meals_on(db: Session, user_id: uuid.UUID, day: date) -> list[Meal]:
    return list(db.scalars(select(Meal).where(Meal.user_id == user_id, Meal.day == day).order_by(Meal.created_at)))


def totals(meals: list[Meal]) -> NutritionTotals:
    return NutritionTotals(
        calories=sum(m.calories for m in meals),
        protein_g=sum(m.protein_g for m in meals),
        carbs_g=sum(m.carbs_g for m in meals),
        fat_g=sum(m.fat_g for m in meals),
    )


def daily_totals(db: Session, user_id: uuid.UUID, start: date, end: date) -> list[DayTotals]:
    rows = db.scalars(select(Meal).where(Meal.user_id == user_id, Meal.day >= start, Meal.day <= end))
    by_day: dict[date, list[Meal]] = defaultdict(list)
    for meal in rows:
        by_day[meal.day].append(meal)
    out, day = [], start
    while day <= end:
        meals = by_day.get(day, [])
        out.append(DayTotals(day=day, meal_count=len(meals), **totals(meals).model_dump()))
        day += timedelta(days=1)
    return out


def update_meal(db: Session, user_id: uuid.UUID, meal_id: uuid.UUID, data: MealUpdate) -> Meal:
    meal = get_owned(db, Meal, meal_id, user_id, "Meal")
    for field, value in data.changes().items():
        setattr(meal, field, value)
    db.commit()
    db.refresh(meal)
    return meal
