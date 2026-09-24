from datetime import date, timedelta

from app.core.errors import AppError
from app.core.time import local_today
from app.modules.users.models import User


class InputError(AppError):
    status_code = 422
    code = "validation_error"


def resolve_range(user: User, start: date | None, end: date | None, *, default_days: int, max_days: int):
    """Default to the last `default_days` ending today (user's timezone); cap the span."""
    today = local_today(user.profile.timezone)
    end = end or today
    start = start or end - timedelta(days=default_days - 1)
    if start > end:
        raise InputError("'from' must be on or before 'to'")
    if (end - start).days >= max_days:
        raise InputError(f"Date range can be at most {max_days} days")
    return start, end


def not_in_future(user: User, day: date, field: str = "path.day") -> None:
    if day > local_today(user.profile.timezone):
        raise InputError(
            "This can't be saved for a future date",
            details=[{"field": field, "message": "Date is in the future"}],
        )
