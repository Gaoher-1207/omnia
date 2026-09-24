import hashlib
import json
import secrets
from datetime import date, time, timedelta

from fastapi import APIRouter, Request, Response, status
from pydantic import BaseModel
from sqlalchemy import select

from app.common.deps import CurrentUser, DbSession
from app.core.config import get_settings
from app.core.errors import NotFoundError
from app.core.rate_limit import limiter
from app.core.time import local_today
from app.modules.activity.models import ActivityDay
from app.modules.ai.models import AIPlan
from app.modules.integrations.ics import Calendar
from app.modules.integrations.models import CalendarFeed
from app.modules.nutrition.models import Meal
from app.modules.sleep.models import SleepLog
from app.modules.social.models import GroupMessage, Post
from app.modules.social.service import friends_overview
from app.modules.study.models import BacklogItem, Exam, StudySession, Subject
from app.modules.tasks.models import Task
from app.modules.users.models import User
from app.modules.users.schemas import ProfileOut

router = APIRouter(tags=["integrations"])


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class CalendarLink(BaseModel):
    url: str
    note: str = "Anyone with this link can read your tasks, exams and today's plan. Revoke it any time."


@router.post(
    "/integrations/calendar",
    response_model=CalendarLink,
    status_code=201,
    summary="Create (or replace) my private calendar subscription link",
)
def create_calendar_link(request: Request, user: CurrentUser, db: DbSession):
    token = secrets.token_urlsafe(32)
    feed = db.get(CalendarFeed, user.id)
    if feed is None:
        db.add(CalendarFeed(user_id=user.id, token_hash=_hash(token)))
    else:
        feed.token_hash = _hash(token)
    db.commit()
    base = get_settings().public_base_url.rstrip("/")
    path = request.app.url_path_for("calendar_feed", token=token)
    return CalendarLink(url=f"{base}{path}" if base else str(request.url_for("calendar_feed", token=token)))


@router.delete("/integrations/calendar", status_code=status.HTTP_204_NO_CONTENT, summary="Revoke my calendar link")
def revoke_calendar_link(user: CurrentUser, db: DbSession):
    feed = db.get(CalendarFeed, user.id)
    if feed is None:
        raise NotFoundError("Calendar link")
    db.delete(feed)
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get(
    "/integrations/calendar/{token}.ics",
    name="calendar_feed",
    summary="Calendar feed for Google/Apple/Outlook (secret link, no login)",
    response_class=Response,
)
def calendar_feed(token: str, request: Request, db: DbSession):
    limiter.hit(f"ics:{request.client.host if request.client else '-'}", 120, 3600)
    feed = db.scalar(select(CalendarFeed).where(CalendarFeed.token_hash == _hash(token)))
    if feed is None:
        raise NotFoundError("Calendar")
    user = db.get(User, feed.user_id)
    tz = user.profile.timezone
    today = local_today(tz)
    cal = Calendar("OMNIA", tz)
    for exam in db.scalars(select(Exam).where(Exam.user_id == user.id, Exam.exam_date >= today - timedelta(days=30))):
        cal.all_day(f"exam-{exam.id}", exam.exam_date, f"Exam: {exam.title}", exam.subject.name)
    tasks = db.scalars(select(Task).where(Task.user_id == user.id, Task.status == "todo", Task.due_date.is_not(None)))
    for task in tasks:
        if task.due_time:
            end = _add_minutes(task.due_time, task.estimated_minutes or 60)
            cal.timed(f"task-{task.id}", task.due_date, task.due_time, end, task.title, task.notes)
        else:
            cal.all_day(f"task-{task.id}", task.due_date, task.title, task.notes)
    plan = db.scalar(
        select(AIPlan)
        .where(AIPlan.user_id == user.id, AIPlan.plan_date == today)
        .order_by(AIPlan.created_at.desc())
        .limit(1)
    )
    if plan:
        for n, item in enumerate(plan.content.get("items", [])):
            if item.get("category") == "task":
                continue  # already listed as a task
            cal.timed(
                f"plan-{plan.id}-{n}",
                today,
                time.fromisoformat(item["start"]),
                time.fromisoformat(item["end"]),
                item["title"],
                item.get("detail"),
            )
    return Response(
        content=cal.render(),
        media_type="text/calendar; charset=utf-8",
        headers={"Cache-Control": "private, max-age=900"},
    )


def _add_minutes(start: time, minutes: int) -> time:
    total = min(start.hour * 60 + start.minute + minutes, 23 * 60 + 59)
    return time(total // 60, total % 60)


# ------------------------------------------------------------------ export


def _rows(db: DbSession, model, user_id, *exclude: str) -> list[dict]:
    skip = {"user_id", *exclude}
    out = []
    for row in db.scalars(select(model).where(model.user_id == user_id)):
        item = {}
        for column in model.__table__.columns:
            if column.key in skip:
                continue
            value = getattr(row, column.key)
            item[column.key] = value.isoformat() if hasattr(value, "isoformat") else value
        out.append(item)
    return out


@router.get("/account/export", summary="Download all my data as JSON")
def export(user: CurrentUser, db: DbSession):
    limiter.hit(f"export:{user.id}", 5, 3600)
    posts = [
        {"kind": p.kind, "body": p.body, "payload": p.payload, "created_at": p.created_at.isoformat()}
        for p in db.scalars(select(Post).where(Post.author_id == user.id))
    ]
    messages = [
        {"group_id": str(m.group_id), "body": m.body, "created_at": m.created_at.isoformat()}
        for m in db.scalars(select(GroupMessage).where(GroupMessage.sender_id == user.id))
    ]
    data = {
        "exported_on": date.today().isoformat(),
        "account": {"email": user.email, "created_at": user.created_at.isoformat()},
        "profile": ProfileOut.model_validate(user.profile).model_dump(mode="json"),
        "tasks": _rows(db, Task, user.id),
        "subjects": _rows(db, Subject, user.id),
        "exams": _rows(db, Exam, user.id),
        "backlog": _rows(db, BacklogItem, user.id),
        "study_sessions": _rows(db, StudySession, user.id),
        "activity": _rows(db, ActivityDay, user.id),
        "sleep": _rows(db, SleepLog, user.id),
        "meals": _rows(db, Meal, user.id),
        "ai_plans": _rows(db, AIPlan, user.id, "fallback_reason"),
        "friends": [f.model_dump(mode="json") for f in friends_overview(db, user).friends],
        "posts": posts,
        "messages_sent": messages,
    }
    return Response(
        content=json.dumps(data, indent=2, default=str),
        media_type="application/json",
        headers={"Content-Disposition": 'attachment; filename="omnia-export.json"', "Cache-Control": "no-store"},
    )
