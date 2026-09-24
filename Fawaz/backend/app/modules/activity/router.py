from datetime import date, timedelta

from fastapi import APIRouter, Query

from app.common.deps import CurrentUser, DbSession
from app.core.errors import AppError
from app.core.time import local_today
from app.modules.activity import service
from app.modules.activity.schemas import ActivityOut, ActivityRange, ActivityUpsert

router = APIRouter(prefix="/activity", tags=["activity"])


class ActivityDateError(AppError):
    status_code = 422
    code = "validation_error"


@router.get("", response_model=ActivityRange, summary="Daily activity for a date range")
def list_activity(
    user: CurrentUser,
    db: DbSession,
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
):
    today = local_today(user.profile.timezone)
    end = end or today
    start = start or end - timedelta(days=13)
    if start > end:
        raise ActivityDateError("'from' must be on or before 'to'")
    if (end - start).days > 92:
        raise ActivityDateError("Date range can be at most 93 days")
    return ActivityRange(
        start=start,
        end=end,
        step_goal=user.profile.daily_step_goal,
        days=service.filled_range(db, user.id, start, end),
    )


@router.get("/{day}", response_model=ActivityOut, summary="Activity for one day")
def get_activity(day: date, user: CurrentUser, db: DbSession):
    row = service.get_day(db, user.id, day)
    return row if row else ActivityOut(day=day)


@router.put("/{day}", response_model=ActivityOut, summary="Save activity for one day (create or replace)")
def put_activity(day: date, body: ActivityUpsert, user: CurrentUser, db: DbSession):
    if day > local_today(user.profile.timezone):
        raise ActivityDateError(
            "Activity can't be saved for a future date",
            details=[{"field": "path.day", "message": "Date is in the future"}],
        )
    return service.upsert_day(db, user.id, day, body)
