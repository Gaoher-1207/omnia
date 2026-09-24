"""Import every model so Base.metadata is complete (used by Alembic and tests)."""

from app.db.base import Base
from app.modules.activity.models import ActivityDay
from app.modules.ai.models import AIPlan
from app.modules.integrations.models import CalendarFeed
from app.modules.nutrition.models import Meal
from app.modules.sleep.models import SleepLog
from app.modules.social.models import (
    Challenge,
    ChallengeParticipant,
    Friendship,
    GroupMember,
    GroupMessage,
    Post,
    PostLike,
    SocialGroup,
)
from app.modules.study.models import BacklogItem, Exam, StudySession, Subject
from app.modules.tasks.models import Task
from app.modules.users.models import Profile, User

__all__ = [
    "AIPlan",
    "ActivityDay",
    "BacklogItem",
    "Base",
    "CalendarFeed",
    "Challenge",
    "ChallengeParticipant",
    "Exam",
    "Friendship",
    "GroupMember",
    "GroupMessage",
    "Post",
    "PostLike",
    "SocialGroup",
    "Meal",
    "SleepLog",
    "Profile",
    "StudySession",
    "Subject",
    "Task",
    "User",
]
