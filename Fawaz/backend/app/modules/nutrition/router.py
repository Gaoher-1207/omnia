import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status

from app.common.dates import InputError, not_in_future, resolve_range
from app.common.deps import CurrentUser, DbSession
from app.common.ownership import get_owned
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.core.time import local_today
from app.modules.nutrition import service
from app.modules.nutrition.estimator import FoodPhotoEstimator, get_estimator
from app.modules.nutrition.models import Meal
from app.modules.nutrition.schemas import (
    DayMeals,
    MealCreate,
    MealOut,
    MealUpdate,
    NutritionSummary,
    PhotoEstimate,
    PhotoEstimateIn,
)

router = APIRouter(tags=["nutrition"])
Estimator = Annotated[FoodPhotoEstimator, Depends(get_estimator)]


@router.get("/meals", response_model=DayMeals, summary="Meals and totals for one day (default today)")
def list_meals(user: CurrentUser, db: DbSession, day: date | None = None):
    day = day or local_today(user.profile.timezone)
    meals = service.meals_on(db, user.id, day)
    return DayMeals(day=day, calorie_goal=user.profile.daily_calorie_goal, totals=service.totals(meals), meals=meals)


@router.post("/meals", response_model=MealOut, status_code=201, summary="Log a meal")
def create_meal(body: MealCreate, user: CurrentUser, db: DbSession):
    day = body.day or local_today(user.profile.timezone)
    not_in_future(user, day, field="body.day")
    meal = Meal(user_id=user.id, **body.model_dump(exclude={"day"}), day=day)
    db.add(meal)
    db.commit()
    db.refresh(meal)
    return meal


@router.patch("/meals/{meal_id}", response_model=MealOut, summary="Edit a meal")
def update_meal(meal_id: uuid.UUID, body: MealUpdate, user: CurrentUser, db: DbSession):
    return service.update_meal(db, user.id, meal_id, body)


@router.delete("/meals/{meal_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Delete a meal")
def delete_meal(meal_id: uuid.UUID, user: CurrentUser, db: DbSession):
    meal = get_owned(db, Meal, meal_id, user.id, "Meal")
    db.delete(meal)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/nutrition/summary", response_model=NutritionSummary, summary="Daily nutrition totals for a range")
def summary(
    user: CurrentUser,
    db: DbSession,
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
):
    start, end = resolve_range(user, start, end, default_days=7, max_days=93)
    return NutritionSummary(
        start=start,
        end=end,
        calorie_goal=user.profile.daily_calorie_goal,
        days=service.daily_totals(db, user.id, start, end),
    )


@router.post(
    "/nutrition/estimate",
    response_model=PhotoEstimate,
    summary="Estimate nutrition from a food photo (not saved)",
    description=(
        "Sends only the photo (and your optional note) to the configured AI provider and returns an estimate. "
        "Nothing is stored; call POST /meals with source='photo_estimate' after the user confirms. "
        "Returns 503 when no AI provider is configured."
    ),
)
def estimate(body: PhotoEstimateIn, user: CurrentUser, estimator: Estimator):
    if not body.looks_like_declared_type():
        raise InputError(
            "The file doesn't look like the image type you sent",
            details=[{"field": "body.image_base64", "message": "Not a valid image of that type"}],
        )
    limiter.hit(f"photo:{user.id}", get_settings().ai_rate_limit_per_hour, 3600)
    return estimator.estimate(body)
