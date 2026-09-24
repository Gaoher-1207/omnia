"""Create a demo account with a week of fictional data.

    python -m app.scripts.seed            # create if missing
    python -m app.scripts.seed --reset    # delete and recreate

Refuses to run when APP_ENV=production. Contains no real person's data.
"""

import argparse
import sys
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.core.config import get_settings
from app.core.security import hash_password
from app.core.time import local_today
from app.db.session import SessionLocal
from app.modules.activity.models import ActivityDay
from app.modules.nutrition.models import Meal
from app.modules.sleep.models import SleepLog
from app.modules.social.models import (
    Challenge,
    ChallengeParticipant,
    Friendship,
    GroupMember,
    GroupMessage,
    Post,
    SocialGroup,
)
from app.modules.study.models import BacklogItem, Exam, StudySession, Subject
from app.modules.tasks.models import Task
from app.modules.users.models import Profile, User

DEMO_EMAIL = "demo@omnia.app"
DEMO_PASSWORD = "omnia-demo-123"  # noqa: S105 - fictional local demo account
DEMO_TZ = "Asia/Kolkata"
FRIEND_EMAIL = "riya.demo@omnia.app"


def seed(reset: bool) -> None:
    if get_settings().is_production:
        sys.exit("Refusing to seed demo data in production.")
    db = SessionLocal()
    try:
        existing = db.scalar(select(User).where(User.email == DEMO_EMAIL))
        if existing and not reset:
            print(f"Demo account already exists: {DEMO_EMAIL}")
            return
        for email in (DEMO_EMAIL, FRIEND_EMAIL):
            old = db.scalar(select(User).where(User.email == email))
            if old:
                db.delete(old)
        db.commit()

        user = User(email=DEMO_EMAIL, password_hash=hash_password(DEMO_PASSWORD))
        user.profile = Profile(
            display_name="Sam",
            timezone=DEMO_TZ,
            daily_study_goal_minutes=240,
            daily_step_goal=8000,
            daily_task_goal=5,
            preferred_workout_time="evening",
            username="sam_demo",
        )
        db.add(user)
        db.flush()
        today = local_today(DEMO_TZ)
        tz = ZoneInfo(DEMO_TZ)

        physics = Subject(user_id=user.id, name="Physics", color="#5b6cff")
        maths = Subject(user_id=user.id, name="Mathematics", color="#e0892b")
        chem = Subject(user_id=user.id, name="Chemistry", color="#1f9d7a")
        db.add_all([physics, maths, chem])
        db.flush()

        db.add_all(
            [
                Exam(
                    user_id=user.id,
                    subject_id=physics.id,
                    title="Physics semester exam",
                    exam_date=today + timedelta(days=8),
                ),
                Exam(
                    user_id=user.id,
                    subject_id=maths.id,
                    title="Calculus II midterm",
                    exam_date=today + timedelta(days=15),
                ),
                Exam(
                    user_id=user.id,
                    subject_id=chem.id,
                    title="Organic chemistry quiz",
                    exam_date=today + timedelta(days=23),
                ),
            ]
        )
        db.add_all(
            [
                BacklogItem(
                    user_id=user.id,
                    subject_id=physics.id,
                    title="Thermodynamics: laws and cycles",
                    estimated_minutes=120,
                ),
                BacklogItem(
                    user_id=user.id, subject_id=physics.id, title="Wave optics problem set", estimated_minutes=90
                ),
                BacklogItem(
                    user_id=user.id,
                    subject_id=physics.id,
                    title="Revise electrostatics formulas",
                    kind="revision",
                    estimated_minutes=45,
                ),
                BacklogItem(
                    user_id=user.id, subject_id=maths.id, title="Integration by parts (arrear)", estimated_minutes=90
                ),
                BacklogItem(
                    user_id=user.id, subject_id=maths.id, title="Series convergence tests", estimated_minutes=60
                ),
                BacklogItem(
                    user_id=user.id, subject_id=chem.id, title="Reaction mechanisms chapter", estimated_minutes=75
                ),
            ]
        )

        study_pattern = [150, 200, 90, 240, 180, 210, 120]
        steps_pattern = [9100, 6400, 8300, 10250, 5200, 8800, 7400]
        workout_pattern = [True, False, True, True, False, True, False]
        for offset in range(7, 0, -1):
            day = today - timedelta(days=offset)
            i = 7 - offset
            minutes = study_pattern[i]
            first = min(minutes, 90)
            db.add(StudySession(user_id=user.id, subject_id=physics.id, session_date=day, duration_minutes=first))
            if minutes > first:
                db.add(
                    StudySession(
                        user_id=user.id, subject_id=maths.id, session_date=day, duration_minutes=minutes - first
                    )
                )
            db.add(
                ActivityDay(
                    user_id=user.id,
                    day=day,
                    steps=steps_pattern[i],
                    workout_done=workout_pattern[i],
                    workout_minutes=40 if workout_pattern[i] else 0,
                    workout_type="Gym" if workout_pattern[i] else None,
                )
            )
            for n in range(2 + i % 3):
                done_at = datetime.combine(day, time(10 + n * 2), tzinfo=tz).astimezone(UTC)
                db.add(
                    Task(
                        user_id=user.id,
                        title=f"Daily admin #{n + 1}",
                        priority="low",
                        status="done",
                        completed_at=done_at,
                    )
                )

        db.add(StudySession(user_id=user.id, subject_id=physics.id, session_date=today, duration_minutes=90))
        db.add(ActivityDay(user_id=user.id, day=today, steps=3200))
        for offset, minutes, quality in ((0, 385, 2), (1, 450, 4), (2, 470, 4), (3, 410, 3)):
            night = today - timedelta(days=offset)
            db.add(SleepLog(user_id=user.id, day=night, duration_minutes=minutes, quality=quality))
        db.add_all(
            [
                Meal(
                    user_id=user.id,
                    day=today,
                    meal_type="breakfast",
                    description="Poha and chai",
                    calories=380,
                    protein_g=8,
                    carbs_g=62,
                    fat_g=10,
                ),
                Meal(
                    user_id=user.id,
                    day=today - timedelta(days=1),
                    meal_type="dinner",
                    description="Dal, rice, salad",
                    calories=620,
                    protein_g=22,
                    carbs_g=98,
                    fat_g=12,
                ),
            ]
        )
        now = datetime.now(UTC)
        db.add_all(
            [
                Task(user_id=user.id, title="Submit physics lab report", priority="high", due_date=today),
                Task(
                    user_id=user.id,
                    title="Email project group about slides",
                    priority="medium",
                    due_date=today + timedelta(days=1),
                ),
                Task(
                    user_id=user.id,
                    title="Book library study room",
                    priority="medium",
                    due_date=today + timedelta(days=2),
                ),
                Task(user_id=user.id, title="Renew bus pass", priority="low"),
                Task(
                    user_id=user.id,
                    title="Read chapter 3 of design notes",
                    priority="low",
                    due_date=today + timedelta(days=5),
                ),
                Task(user_id=user.id, title="Pay hostel fees", priority="high", status="done", completed_at=now),
            ]
        )
        db.flush()
        _seed_social(db, user, today)
        db.commit()
        print(f"Seeded demo account {DEMO_EMAIL} / {DEMO_PASSWORD} (friend: {FRIEND_EMAIL}, same password)")
    finally:
        db.close()


def _seed_social(db, user: User, today) -> None:
    """A fictional friend, a shared group with a little chat, a challenge and a post."""
    friend = User(email=FRIEND_EMAIL, password_hash=hash_password(DEMO_PASSWORD))
    friend.profile = Profile(display_name="Riya", timezone=DEMO_TZ, username="riya_demo")
    db.add(friend)
    db.flush()
    db.add(Friendship(requester_id=user.id, addressee_id=friend.id, status="accepted"))
    group = SocialGroup(owner_id=user.id, name="Study Squad", description="Semester exam prep")
    db.add(group)
    db.flush()
    db.add_all(
        [
            GroupMember(group_id=group.id, user_id=user.id, role="owner"),
            GroupMember(group_id=group.id, user_id=friend.id, role="member"),
            GroupMessage(group_id=group.id, sender_id=friend.id, body="Library at 5 today?"),
            GroupMessage(group_id=group.id, sender_id=user.id, body="Yes! Bringing the thermo notes."),
        ]
    )
    challenge = Challenge(
        group_id=group.id,
        created_by=user.id,
        title="20 study sessions this week",
        metric="study_sessions",
        target=20,
        start_date=today - timedelta(days=today.weekday()),
        end_date=today - timedelta(days=today.weekday()) + timedelta(days=6),
    )
    db.add(challenge)
    db.flush()
    db.add_all(
        [
            ChallengeParticipant(challenge_id=challenge.id, user_id=user.id),
            ChallengeParticipant(challenge_id=challenge.id, user_id=friend.id),
            Post(
                author_id=friend.id,
                kind="progress",
                body="Finally finished the optics backlog!",
                payload={"date": today.isoformat(), "study_minutes": 210, "study_streak": 4},
            ),
        ]
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reset", action="store_true", help="delete and recreate the demo account")
    seed(parser.parse_args().reset)
