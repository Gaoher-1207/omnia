import uuid
from datetime import UTC, date, datetime, time, timedelta

from sqlalchemy import and_, false, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.common.dates import InputError
from app.core.errors import AppError, ConflictError, NotFoundError
from app.core.time import local_today, to_local_date
from app.modules.activity.models import ActivityDay
from app.modules.progress import service as progress_service
from app.modules.progress.achievements import BY_CODE
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
from app.modules.social.schemas import (
    ChallengeCreate,
    ChallengeOut,
    FriendRequestOut,
    FriendsOut,
    GroupDetail,
    GroupMemberOut,
    GroupOut,
    LeaderboardRow,
    MessageOut,
    PostIn,
    PostOut,
    PublicUser,
)
from app.modules.study.models import StudySession
from app.modules.tasks.models import Task
from app.modules.users.models import Profile, User


class ForbiddenError(AppError):
    status_code = 403
    code = "forbidden"


def public(user: User) -> PublicUser:
    return PublicUser(id=user.id, display_name=user.profile.display_name, username=user.profile.username)


def _users(db: Session, ids: set[uuid.UUID]) -> dict[uuid.UUID, User]:
    if not ids:
        return {}
    return {u.id: u for u in db.scalars(select(User).where(User.id.in_(ids))).unique()}


# ------------------------------------------------------------------ friends


def find_by_username(db: Session, username: str) -> User:
    user = db.scalar(select(User).join(Profile).where(Profile.username == username.strip().lower()))
    if user is None:
        raise NotFoundError("User")
    return user


def _pair(db: Session, a: uuid.UUID, b: uuid.UUID) -> Friendship | None:
    return db.scalar(
        select(Friendship).where(
            or_(
                and_(Friendship.requester_id == a, Friendship.addressee_id == b),
                and_(Friendship.requester_id == b, Friendship.addressee_id == a),
            )
        )
    )


def friend_ids(db: Session, user_id: uuid.UUID) -> set[uuid.UUID]:
    rows = db.execute(
        select(Friendship.requester_id, Friendship.addressee_id).where(
            Friendship.status == "accepted",
            or_(Friendship.requester_id == user_id, Friendship.addressee_id == user_id),
        )
    )
    return {b if a == user_id else a for a, b in rows}


def are_friends(db: Session, a: uuid.UUID, b: uuid.UUID) -> bool:
    link = _pair(db, a, b)
    return link is not None and link.status == "accepted"


def send_request(db: Session, me: User, username: str) -> Friendship:
    other = find_by_username(db, username)
    if other.id == me.id:
        raise InputError("You can't add yourself", details=[{"field": "body.username", "message": "That's you"}])
    existing = _pair(db, me.id, other.id)
    if existing is not None:
        if existing.status == "accepted":
            raise ConflictError("You're already friends")
        if existing.addressee_id == me.id:  # they asked first: accept instead of duplicating
            existing.status = "accepted"
            db.commit()
            return existing
        raise ConflictError("Friend request already sent")
    link = Friendship(requester_id=me.id, addressee_id=other.id, status="pending")
    db.add(link)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ConflictError("Friend request already sent") from None
    return link


def respond(db: Session, me: User, request_id: uuid.UUID, accept: bool) -> None:
    link = db.get(Friendship, request_id)
    if link is None or link.addressee_id != me.id or link.status != "pending":
        raise NotFoundError("Friend request")
    if accept:
        link.status = "accepted"
    else:
        db.delete(link)
    db.commit()


def remove_friend(db: Session, me: User, other_id: uuid.UUID) -> None:
    link = _pair(db, me.id, other_id)
    if link is None:
        raise NotFoundError("Friend")
    db.delete(link)
    db.commit()


def friends_overview(db: Session, me: User) -> FriendsOut:
    links = list(
        db.scalars(select(Friendship).where(or_(Friendship.requester_id == me.id, Friendship.addressee_id == me.id)))
    )
    users = _users(db, {lnk.requester_id for lnk in links} | {lnk.addressee_id for lnk in links})
    friends, incoming, outgoing = [], [], []
    for link in links:
        other = users[link.addressee_id if link.requester_id == me.id else link.requester_id]
        if link.status == "accepted":
            friends.append(public(other))
        elif link.addressee_id == me.id:
            incoming.append(FriendRequestOut(id=link.id, user=public(other), created_at=link.created_at))
        else:
            outgoing.append(FriendRequestOut(id=link.id, user=public(other), created_at=link.created_at))
    friends.sort(key=lambda u: u.display_name.lower())
    return FriendsOut(friends=friends, incoming=incoming, outgoing=outgoing)


# ------------------------------------------------------------------- groups


def membership(db: Session, group_id: uuid.UUID, user_id: uuid.UUID) -> GroupMember:
    """The caller's membership, or 404 so non-members can't learn a group exists."""
    member = db.get(GroupMember, (group_id, user_id))
    if member is None:
        raise NotFoundError("Group")
    return member


def _group_out(db: Session, group: SocialGroup, role: str) -> GroupOut:
    count = db.scalar(select(func.count()).select_from(GroupMember).where(GroupMember.group_id == group.id)) or 0
    return GroupOut(
        id=group.id,
        name=group.name,
        description=group.description,
        owner_id=group.owner_id,
        my_role=role,
        member_count=count,
        created_at=group.created_at,
    )


def list_groups(db: Session, me: User) -> list[GroupOut]:
    rows = db.execute(
        select(SocialGroup, GroupMember.role)
        .join(GroupMember, GroupMember.group_id == SocialGroup.id)
        .where(GroupMember.user_id == me.id)
        .order_by(SocialGroup.name)
    )
    return [_group_out(db, group, role) for group, role in rows]


def create_group(db: Session, me: User, name: str, description: str | None) -> GroupOut:
    group = SocialGroup(owner_id=me.id, name=name, description=description)
    db.add(group)
    db.flush()
    db.add(GroupMember(group_id=group.id, user_id=me.id, role="owner"))
    db.commit()
    db.refresh(group)
    return _group_out(db, group, "owner")


def group_detail(db: Session, me: User, group_id: uuid.UUID) -> GroupDetail:
    mine = membership(db, group_id, me.id)
    group = db.get(SocialGroup, group_id)
    members = list(db.scalars(select(GroupMember).where(GroupMember.group_id == group_id)))
    users = _users(db, {m.user_id for m in members})
    base = _group_out(db, group, mine.role)
    return GroupDetail(
        **base.model_dump(),
        members=[
            GroupMemberOut(user=public(users[m.user_id]), role=m.role, joined_at=m.joined_at)
            for m in sorted(members, key=lambda m: (m.role != "owner", m.joined_at))
        ],
    )


def _require_owner(db: Session, me: User, group_id: uuid.UUID) -> SocialGroup:
    if membership(db, group_id, me.id).role != "owner":
        raise ForbiddenError("Only the group owner can do that")
    return db.get(SocialGroup, group_id)


def update_group(db: Session, me: User, group_id: uuid.UUID, changes: dict) -> GroupOut:
    group = _require_owner(db, me, group_id)
    for field, value in changes.items():
        setattr(group, field, value)
    db.commit()
    return _group_out(db, group, "owner")


def delete_group(db: Session, me: User, group_id: uuid.UUID) -> None:
    group = _require_owner(db, me, group_id)
    db.delete(group)
    db.commit()


def add_member(db: Session, me: User, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    _require_owner(db, me, group_id)
    if not are_friends(db, me.id, user_id):
        raise ForbiddenError("You can only add your friends to a group")
    if db.get(GroupMember, (group_id, user_id)) is not None:
        raise ConflictError("Already a member")
    db.add(GroupMember(group_id=group_id, user_id=user_id, role="member"))
    db.commit()


def remove_member(db: Session, me: User, group_id: uuid.UUID, user_id: uuid.UUID) -> None:
    mine = membership(db, group_id, me.id)
    if user_id != me.id and mine.role != "owner":
        raise ForbiddenError("Only the group owner can remove members")
    target = db.get(GroupMember, (group_id, user_id))
    if target is None:
        raise NotFoundError("Member")
    if target.role == "owner":
        raise ConflictError("The owner can't leave; delete the group instead")
    db.delete(target)
    db.commit()


# --------------------------------------------------------------------- chat


def list_messages(db: Session, me: User, group_id: uuid.UUID, after: datetime | None, limit: int) -> list[MessageOut]:
    membership(db, group_id, me.id)
    query = select(GroupMessage).where(GroupMessage.group_id == group_id)
    if after is not None:
        query = query.where(GroupMessage.created_at > after).order_by(GroupMessage.created_at).limit(limit)
        rows = list(db.scalars(query))
    else:  # latest page, returned oldest-first for display
        rows = list(db.scalars(query.order_by(GroupMessage.created_at.desc()).limit(limit)))[::-1]
    users = _users(db, {m.sender_id for m in rows})
    return [
        MessageOut(
            id=m.id, sender=public(users[m.sender_id]), body=m.body, created_at=m.created_at, mine=m.sender_id == me.id
        )
        for m in rows
    ]


def send_message(db: Session, me: User, group_id: uuid.UUID, body: str) -> MessageOut:
    membership(db, group_id, me.id)
    message = GroupMessage(group_id=group_id, sender_id=me.id, body=body)
    db.add(message)
    db.commit()
    db.refresh(message)
    return MessageOut(id=message.id, sender=public(me), body=message.body, created_at=message.created_at, mine=True)


# --------------------------------------------------------------------- feed


def _snapshot(db: Session, me: User, fields: list[str]) -> dict:
    """Today's real numbers, read on the server; the client only picks which ones to share."""
    progress = progress_service.progress(db, me, history_days=1)
    today = progress.history[-1]
    streaks = progress.streaks
    available = {
        "study_minutes": today.study_minutes,
        "tasks_completed": today.tasks_completed,
        "steps": today.steps,
        "workout_done": today.workout_done,
        "study_streak": streaks.study.current,
        "balance_streak": streaks.balance.current,
        "fitness_streak": streaks.fitness.current,
    }
    return {"date": today.date.isoformat(), **{f: available[f] for f in dict.fromkeys(fields)}}


def create_post(db: Session, me: User, data: PostIn) -> PostOut:
    visibility = "friends"
    if data.group_id is not None:
        membership(db, data.group_id, me.id)
        visibility = "group"
    payload: dict = {}
    if data.kind == "progress":
        payload = _snapshot(db, me, data.share)
    elif data.kind == "achievement":
        definition = BY_CODE.get(data.achievement_code or "")
        earned = {a.code for a in progress_service.achievements(db, me) if a.earned}
        if definition is None or definition.code not in earned:
            raise InputError(
                "You can only share achievements you've earned",
                details=[{"field": "body.achievement_code", "message": "Not earned"}],
            )
        payload = {"code": definition.code, "title": definition.title, "description": definition.description}
    post = Post(
        author_id=me.id,
        kind=data.kind,
        body=data.text.strip() if data.text and data.text.strip() else None,
        payload=payload,
        visibility=visibility,
        group_id=data.group_id,
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return _posts_out(db, me, [post])[0]


def _visible_filter(db: Session, me: User):
    friends = friend_ids(db, me.id)
    my_groups = select(GroupMember.group_id).where(GroupMember.user_id == me.id)
    return or_(
        Post.author_id == me.id,
        and_(Post.visibility == "friends", Post.author_id.in_(friends)) if friends else false(),
        and_(Post.visibility == "group", Post.group_id.in_(my_groups)),
    )


def feed(db: Session, me: User, before: datetime | None, limit: int) -> list[PostOut]:
    query = select(Post).where(_visible_filter(db, me))
    if before is not None:
        query = query.where(Post.created_at < before)
    posts = list(db.scalars(query.order_by(Post.created_at.desc()).limit(limit)))
    return _posts_out(db, me, posts)


def _posts_out(db: Session, me: User, posts: list[Post]) -> list[PostOut]:
    if not posts:
        return []
    ids = [p.id for p in posts]
    counts = {
        post_id: count
        for post_id, count in db.execute(
            select(PostLike.post_id, func.count()).where(PostLike.post_id.in_(ids)).group_by(PostLike.post_id)
        ).all()
    }
    liked = set(db.scalars(select(PostLike.post_id).where(PostLike.post_id.in_(ids), PostLike.user_id == me.id)))
    authors = _users(db, {p.author_id for p in posts})
    group_names = {
        g.id: g.name
        for g in db.scalars(select(SocialGroup).where(SocialGroup.id.in_({p.group_id for p in posts if p.group_id})))
    }
    return [
        PostOut(
            id=p.id,
            author=public(authors[p.author_id]),
            kind=p.kind,
            body=p.body,
            payload=p.payload,
            visibility=p.visibility,
            group_id=p.group_id,
            group_name=group_names.get(p.group_id),
            like_count=counts.get(p.id, 0),
            liked_by_me=p.id in liked,
            mine=p.author_id == me.id,
            created_at=p.created_at,
        )
        for p in posts
    ]


def visible_post(db: Session, me: User, post_id: uuid.UUID) -> Post:
    post = db.scalar(select(Post).where(Post.id == post_id, _visible_filter(db, me)))
    if post is None:
        raise NotFoundError("Post")
    return post


def delete_post(db: Session, me: User, post_id: uuid.UUID) -> None:
    post = db.get(Post, post_id)
    if post is None or post.author_id != me.id:
        raise NotFoundError("Post")
    db.delete(post)
    db.commit()


def set_like(db: Session, me: User, post_id: uuid.UUID, liked: bool) -> PostOut:
    post = visible_post(db, me, post_id)
    existing = db.get(PostLike, (post_id, me.id))
    if liked and existing is None:
        db.add(PostLike(post_id=post_id, user_id=me.id))
    elif not liked and existing is not None:
        db.delete(existing)
    try:
        db.commit()
    except IntegrityError:  # double tap: the like already exists
        db.rollback()
    return _posts_out(db, me, [post])[0]


# --------------------------------------------------------------- challenges


def _metric_value(db: Session, user: User, metric: str, start: date, end: date) -> int:
    if metric in ("study_minutes", "study_sessions"):
        agg = func.sum(StudySession.duration_minutes) if metric == "study_minutes" else func.count()
        return int(
            db.scalar(select(agg).where(StudySession.user_id == user.id, StudySession.session_date.between(start, end)))
            or 0
        )
    if metric in ("steps", "workouts"):
        agg = func.sum(ActivityDay.steps) if metric == "steps" else func.count()
        query = select(agg).where(ActivityDay.user_id == user.id, ActivityDay.day.between(start, end))
        if metric == "workouts":
            query = query.where(ActivityDay.workout_done.is_(True))
        return int(db.scalar(query) or 0)
    # tasks_completed, counted on the user's own local calendar days
    lo = datetime.combine(start - timedelta(days=1), time.min, tzinfo=UTC)
    hi = datetime.combine(end + timedelta(days=2), time.min, tzinfo=UTC)
    moments = db.scalars(
        select(Task.completed_at).where(
            Task.user_id == user.id, Task.status == "done", Task.completed_at >= lo, Task.completed_at < hi
        )
    )
    tz = user.profile.timezone
    return sum(1 for m in moments if m and start <= to_local_date(m, tz) <= end)


def _challenge_out(db: Session, me: User, challenge: Challenge) -> ChallengeOut:
    participant_ids = set(
        db.scalars(select(ChallengeParticipant.user_id).where(ChallengeParticipant.challenge_id == challenge.id))
    )
    users = _users(db, participant_ids)
    end = min(challenge.end_date, local_today(me.profile.timezone))
    rows = []
    for user in users.values():
        value = (
            _metric_value(db, user, challenge.metric, challenge.start_date, end) if end >= challenge.start_date else 0
        )
        rows.append(LeaderboardRow(user=public(user), value=value, completed=value >= challenge.target))
    rows.sort(key=lambda r: (-r.value, r.user.display_name.lower()))
    return ChallengeOut(
        id=challenge.id,
        group_id=challenge.group_id,
        title=challenge.title,
        metric=challenge.metric,
        target=challenge.target,
        start_date=challenge.start_date,
        end_date=challenge.end_date,
        joined=me.id in participant_ids,
        participant_count=len(rows),
        group_total=sum(r.value for r in rows),
        leaderboard=rows,
    )


def list_challenges(db: Session, me: User, group_id: uuid.UUID) -> list[ChallengeOut]:
    membership(db, group_id, me.id)
    challenges = db.scalars(select(Challenge).where(Challenge.group_id == group_id).order_by(Challenge.end_date.desc()))
    return [_challenge_out(db, me, c) for c in challenges]


def create_challenge(db: Session, me: User, group_id: uuid.UUID, data: ChallengeCreate) -> ChallengeOut:
    membership(db, group_id, me.id)
    challenge = Challenge(group_id=group_id, created_by=me.id, **data.model_dump())
    db.add(challenge)
    db.flush()
    db.add(ChallengeParticipant(challenge_id=challenge.id, user_id=me.id))
    db.commit()
    return _challenge_out(db, me, challenge)


def _challenge_for_member(db: Session, me: User, challenge_id: uuid.UUID) -> Challenge:
    challenge = db.get(Challenge, challenge_id)
    if challenge is None or db.get(GroupMember, (challenge.group_id, me.id)) is None:
        raise NotFoundError("Challenge")
    return challenge


def get_challenge(db: Session, me: User, challenge_id: uuid.UUID) -> ChallengeOut:
    return _challenge_out(db, me, _challenge_for_member(db, me, challenge_id))


def set_participation(db: Session, me: User, challenge_id: uuid.UUID, join: bool) -> ChallengeOut:
    challenge = _challenge_for_member(db, me, challenge_id)
    existing = db.get(ChallengeParticipant, (challenge_id, me.id))
    if join and existing is None:
        db.add(ChallengeParticipant(challenge_id=challenge_id, user_id=me.id))
    elif not join and existing is not None:
        db.delete(existing)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
    return _challenge_out(db, me, challenge)
