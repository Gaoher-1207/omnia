from datetime import date

from fastapi import APIRouter, Query, Response, status

from app.common.dates import not_in_future, resolve_range
from app.common.deps import CurrentUser, DbSession
from app.core.errors import NotFoundError
from app.modules.sleep import service
from app.modules.sleep.schemas import SleepOut, SleepRange, SleepUpsert

router = APIRouter(prefix="/sleep", tags=["sleep"])


@router.get("", response_model=SleepRange, summary="Sleep for a date range (default last 14 days)")
def list_sleep(
    user: CurrentUser,
    db: DbSession,
    start: date | None = Query(default=None, alias="from"),
    end: date | None = Query(default=None, alias="to"),
):
    start, end = resolve_range(user, start, end, default_days=14, max_days=93)
    days = service.filled_range(db, user.id, start, end)
    logged = [d.duration_minutes for d in days if d.logged]
    return SleepRange(
        start=start,
        end=end,
        goal_minutes=user.profile.daily_sleep_goal_minutes,
        average_minutes=round(sum(logged) / len(logged)) if logged else None,
        days=days,
    )


@router.get("/{day}", response_model=SleepOut, summary="Sleep for the night ending on a day")
def get_sleep(day: date, user: CurrentUser, db: DbSession):
    row = service.get_day(db, user.id, day)
    return row if row else SleepOut(day=day, logged=False)


@router.put("/{day}", response_model=SleepOut, summary="Save sleep for a day (create or replace)")
def put_sleep(day: date, body: SleepUpsert, user: CurrentUser, db: DbSession):
    not_in_future(user, day)
    return service.upsert_day(db, user.id, day, body)


@router.delete("/{day}", status_code=status.HTTP_204_NO_CONTENT, summary="Remove the sleep entry for a day")
def delete_sleep(day: date, user: CurrentUser, db: DbSession):
    row = service.get_day(db, user.id, day)
    if row is None:
        raise NotFoundError("Sleep entry")
    db.delete(row)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
