import uuid
from datetime import datetime

from fastapi import APIRouter, Query, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.rate_limit import limiter
from app.modules.social import service
from app.modules.social.schemas import (
    AddMemberIn,
    ChallengeCreate,
    ChallengeOut,
    FriendRequestIn,
    FriendsOut,
    GroupCreate,
    GroupDetail,
    GroupOut,
    GroupUpdate,
    MessageIn,
    MessageOut,
    PostIn,
    PostOut,
    PublicUser,
)

router = APIRouter(prefix="/social", tags=["social"])
_NO_CONTENT = status.HTTP_204_NO_CONTENT


def _done() -> Response:
    return Response(status_code=_NO_CONTENT)


# ---- people


@router.get("/users/{username}", response_model=PublicUser, summary="Look up someone by exact username")
def find_user(username: str, user: CurrentUser, db: DbSession):
    limiter.hit(f"lookup:{user.id}", 60, 60)
    return service.public(service.find_by_username(db, username))


@router.get("/friends", response_model=FriendsOut, summary="My friends and pending requests")
def friends(user: CurrentUser, db: DbSession):
    return service.friends_overview(db, user)


@router.post("/friends/requests", status_code=201, response_model=FriendsOut, summary="Send a friend request")
def request_friend(body: FriendRequestIn, user: CurrentUser, db: DbSession):
    limiter.hit(f"friend-request:{user.id}", 30, 3600)
    service.send_request(db, user, body.username)
    return service.friends_overview(db, user)


@router.post("/friends/requests/{request_id}/accept", response_model=FriendsOut, summary="Accept a request")
def accept(request_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.respond(db, user, request_id, accept=True)
    return service.friends_overview(db, user)


@router.post("/friends/requests/{request_id}/decline", response_model=FriendsOut, summary="Decline a request")
def decline(request_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.respond(db, user, request_id, accept=False)
    return service.friends_overview(db, user)


@router.delete("/friends/{user_id}", status_code=_NO_CONTENT, summary="Unfriend, or cancel a request")
def unfriend(user_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.remove_friend(db, user, user_id)
    return _done()


# ---- groups


@router.get("/groups", response_model=list[GroupOut], summary="Groups I belong to")
def groups(user: CurrentUser, db: DbSession):
    return service.list_groups(db, user)


@router.post("/groups", response_model=GroupOut, status_code=201, summary="Create a group (you're the owner)")
def create_group(body: GroupCreate, user: CurrentUser, db: DbSession):
    return service.create_group(db, user, body.name, body.description)


@router.get("/groups/{group_id}", response_model=GroupDetail, summary="Group details and members")
def group(group_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.group_detail(db, user, group_id)


@router.patch("/groups/{group_id}", response_model=GroupOut, summary="Rename a group (owner)")
def update_group(group_id: uuid.UUID, body: GroupUpdate, user: CurrentUser, db: DbSession):
    return service.update_group(db, user, group_id, body.changes())


@router.delete("/groups/{group_id}", status_code=_NO_CONTENT, summary="Delete a group (owner)")
def delete_group(group_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_group(db, user, group_id)
    return _done()


@router.post("/groups/{group_id}/members", response_model=GroupDetail, summary="Add a friend to the group (owner)")
def add_member(group_id: uuid.UUID, body: AddMemberIn, user: CurrentUser, db: DbSession):
    service.add_member(db, user, group_id, body.user_id)
    return service.group_detail(db, user, group_id)


@router.delete(
    "/groups/{group_id}/members/{user_id}", status_code=_NO_CONTENT, summary="Leave, or remove a member (owner)"
)
def remove_member(group_id: uuid.UUID, user_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.remove_member(db, user, group_id, user_id)
    return _done()


# ---- chat


@router.get("/groups/{group_id}/messages", response_model=list[MessageOut], summary="Group chat messages")
def messages(
    group_id: uuid.UUID,
    user: CurrentUser,
    db: DbSession,
    after: datetime | None = Query(default=None, description="Only messages newer than this (for polling)"),
    limit: int = Query(default=50, ge=1, le=200),
):
    return service.list_messages(db, user, group_id, after, limit)


@router.post("/groups/{group_id}/messages", response_model=MessageOut, status_code=201, summary="Send a message")
def send(group_id: uuid.UUID, body: MessageIn, user: CurrentUser, db: DbSession):
    limiter.hit(f"chat:{user.id}", 30, 60)
    return service.send_message(db, user, group_id, body.body)


# ---- feed


@router.get("/feed", response_model=list[PostOut], summary="Posts from me, my friends and my groups")
def feed(
    user: CurrentUser,
    db: DbSession,
    before: datetime | None = Query(default=None, description="For paging: posts older than this"),
    limit: int = Query(default=30, ge=1, le=100),
):
    return service.feed(db, user, before, limit)


@router.post("/posts", response_model=PostOut, status_code=201, summary="Share progress, an achievement, or a note")
def post(body: PostIn, user: CurrentUser, db: DbSession):
    limiter.hit(f"post:{user.id}", 20, 3600)
    return service.create_post(db, user, body)


@router.delete("/posts/{post_id}", status_code=_NO_CONTENT, summary="Delete my post")
def delete_post(post_id: uuid.UUID, user: CurrentUser, db: DbSession):
    service.delete_post(db, user, post_id)
    return _done()


@router.post("/posts/{post_id}/like", response_model=PostOut, summary="Like a post")
def like(post_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.set_like(db, user, post_id, liked=True)


@router.delete("/posts/{post_id}/like", response_model=PostOut, summary="Remove my like")
def unlike(post_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.set_like(db, user, post_id, liked=False)


# ---- challenges


@router.get("/groups/{group_id}/challenges", response_model=list[ChallengeOut], summary="Group challenges")
def challenges(group_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.list_challenges(db, user, group_id)


@router.post("/groups/{group_id}/challenges", response_model=ChallengeOut, status_code=201, summary="Start a challenge")
def create_challenge(group_id: uuid.UUID, body: ChallengeCreate, user: CurrentUser, db: DbSession):
    return service.create_challenge(db, user, group_id, body)


@router.get("/challenges/{challenge_id}", response_model=ChallengeOut, summary="Challenge leaderboard")
def challenge(challenge_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.get_challenge(db, user, challenge_id)


@router.post("/challenges/{challenge_id}/join", response_model=ChallengeOut, summary="Join (share your progress)")
def join(challenge_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.set_participation(db, user, challenge_id, join=True)


@router.delete("/challenges/{challenge_id}/join", response_model=ChallengeOut, summary="Leave a challenge")
def leave(challenge_id: uuid.UUID, user: CurrentUser, db: DbSession):
    return service.set_participation(db, user, challenge_id, join=False)
