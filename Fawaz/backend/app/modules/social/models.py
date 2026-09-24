"""Phase 3 social data: friends, groups, chat, progress feed, challenges.

Privacy model: nothing here is public. Friends are mutual and opt-in, groups are
invite-only (the owner can only add their own friends), posts are shared on
purpose with friends or one group, and challenge progress is only computed for
people who joined that challenge.
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, IdMixin, TimestampMixin, _now
from app.db.types import UTCDateTime

_USER_FK = "users.id"


class Friendship(IdMixin, TimestampMixin, Base):
    __tablename__ = "friendships"
    __table_args__ = (
        UniqueConstraint("requester_id", "addressee_id", name="uq_friendships_pair"),
        CheckConstraint("requester_id <> addressee_id", name="not_self"),
        CheckConstraint("status IN ('pending', 'accepted')", name="status"),
        Index("ix_friendships_addressee_status", "addressee_id", "status"),
    )

    requester_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), nullable=False, index=True
    )
    addressee_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), nullable=False)
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="pending")


class SocialGroup(IdMixin, TimestampMixin, Base):
    __tablename__ = "social_groups"

    owner_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(60), nullable=False)
    description: Mapped[str | None] = mapped_column(String(300))

    members: Mapped[list["GroupMember"]] = relationship(
        back_populates="group", cascade="all, delete-orphan", passive_deletes=True
    )


class GroupMember(Base):
    __tablename__ = "group_members"
    __table_args__ = (CheckConstraint("role IN ('owner', 'member')", name="role"),)

    group_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("social_groups.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), primary_key=True, index=True
    )
    role: Mapped[str] = mapped_column(String(10), nullable=False, default="member")
    joined_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=_now)

    group: Mapped[SocialGroup] = relationship(back_populates="members")


class GroupMessage(IdMixin, Base):
    __tablename__ = "group_messages"
    __table_args__ = (Index("ix_group_messages_group_created", "group_id", "created_at"),)

    group_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("social_groups.id", ondelete="CASCADE"), nullable=False
    )
    sender_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), nullable=False, index=True
    )
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=_now)


class Post(IdMixin, Base):
    """A progress update the user chose to share. Numbers are captured server-side at posting time."""

    __tablename__ = "posts"
    __table_args__ = (
        CheckConstraint("kind IN ('progress', 'achievement', 'text')", name="kind"),
        CheckConstraint("visibility IN ('friends', 'group')", name="visibility"),
        Index("ix_posts_author_created", "author_id", "created_at"),
        Index("ix_posts_group_created", "group_id", "created_at"),
    )

    author_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), nullable=False)
    kind: Mapped[str] = mapped_column(String(12), nullable=False)
    body: Mapped[str | None] = mapped_column(String(500))
    payload: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    visibility: Mapped[str] = mapped_column(String(10), nullable=False, default="friends")
    group_id: Mapped[uuid.UUID | None] = mapped_column(Uuid, ForeignKey("social_groups.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=_now)


class PostLike(Base):
    __tablename__ = "post_likes"

    post_id: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey("posts.id", ondelete="CASCADE"), primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), primary_key=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=_now)


class Challenge(IdMixin, TimestampMixin, Base):
    __tablename__ = "challenges"
    __table_args__ = (
        CheckConstraint(
            "metric IN ('study_minutes', 'study_sessions', 'steps', 'tasks_completed', 'workouts')", name="metric"
        ),
        CheckConstraint("target > 0", name="target_positive"),
        CheckConstraint("end_date >= start_date", name="dates_ordered"),
    )

    group_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("social_groups.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_by: Mapped[uuid.UUID] = mapped_column(Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String(100), nullable=False)
    metric: Mapped[str] = mapped_column(String(20), nullable=False)
    target: Mapped[int] = mapped_column(Integer, nullable=False)
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)


class ChallengeParticipant(Base):
    __tablename__ = "challenge_participants"

    challenge_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey("challenges.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid, ForeignKey(_USER_FK, ondelete="CASCADE"), primary_key=True, index=True
    )
    joined_at: Mapped[datetime] = mapped_column(UTCDateTime, nullable=False, default=_now)
