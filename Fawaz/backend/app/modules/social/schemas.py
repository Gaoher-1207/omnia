import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.common.schemas import InputModel, PatchModel, Text

Metric = Literal["study_minutes", "study_sessions", "steps", "tasks_completed", "workouts"]
ShareField = Literal[
    "study_minutes", "tasks_completed", "steps", "workout_done", "study_streak", "balance_streak", "fitness_streak"
]


class PublicUser(BaseModel):
    """The only fields other users ever see about someone."""

    id: uuid.UUID
    display_name: str
    username: str | None


class FriendRequestIn(InputModel):
    username: str = Field(min_length=3, max_length=30)

    @field_validator("username")
    @classmethod
    def _norm(cls, v: str) -> str:
        return v.strip().lower().lstrip("@")


class FriendRequestOut(BaseModel):
    id: uuid.UUID
    user: PublicUser
    created_at: datetime


class FriendsOut(BaseModel):
    friends: list[PublicUser]
    incoming: list[FriendRequestOut]
    outgoing: list[FriendRequestOut]


class GroupCreate(InputModel):
    name: Text(60)
    description: str | None = Field(default=None, max_length=300)


class GroupUpdate(PatchModel):
    non_nullable = frozenset({"name"})
    name: Text(60) | None = None
    description: str | None = Field(default=None, max_length=300)


class GroupMemberOut(BaseModel):
    user: PublicUser
    role: Literal["owner", "member"]
    joined_at: datetime


class GroupOut(BaseModel):
    id: uuid.UUID
    name: str
    description: str | None
    owner_id: uuid.UUID
    my_role: Literal["owner", "member"]
    member_count: int
    created_at: datetime


class GroupDetail(GroupOut):
    members: list[GroupMemberOut]


class AddMemberIn(InputModel):
    user_id: uuid.UUID


class MessageIn(InputModel):
    body: Text(2000)


class MessageOut(BaseModel):
    id: uuid.UUID
    sender: PublicUser
    body: str
    created_at: datetime
    mine: bool


class PostIn(InputModel):
    kind: Literal["progress", "achievement", "text"]
    text: str | None = Field(default=None, max_length=500)
    share: list[ShareField] = Field(
        default_factory=list, max_length=7, description="For progress posts: which of today's numbers to include"
    )
    achievement_code: str | None = Field(default=None, max_length=40)
    group_id: uuid.UUID | None = Field(default=None, description="Share with one group instead of all friends")

    @model_validator(mode="after")
    def _shape(self):
        if self.kind == "progress" and not self.share:
            raise ValueError("Choose at least one number to share")
        if self.kind == "achievement" and not self.achievement_code:
            raise ValueError("achievement_code is required for achievement posts")
        if self.kind == "text" and not (self.text and self.text.strip()):
            raise ValueError("text is required for text posts")
        return self


class PostOut(BaseModel):
    id: uuid.UUID
    author: PublicUser
    kind: str
    body: str | None
    payload: dict
    visibility: Literal["friends", "group"]
    group_id: uuid.UUID | None
    group_name: str | None = None
    like_count: int
    liked_by_me: bool
    mine: bool
    created_at: datetime


class ChallengeCreate(InputModel):
    title: Text(100)
    metric: Metric
    target: int = Field(gt=0, le=1_000_000)
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def _dates(self):
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        if (self.end_date - self.start_date).days > 92:
            raise ValueError("A challenge can last at most 93 days")
        return self


class LeaderboardRow(BaseModel):
    user: PublicUser
    value: int
    completed: bool


class ChallengeOut(BaseModel):
    id: uuid.UUID
    group_id: uuid.UUID
    title: str
    metric: Metric
    target: int
    start_date: date
    end_date: date
    joined: bool
    participant_count: int
    group_total: int
    leaderboard: list[LeaderboardRow]
