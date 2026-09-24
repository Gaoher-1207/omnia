from fastapi import APIRouter
from sqlalchemy.exc import IntegrityError

from app.common.deps import CurrentUser, DbSession
from app.core.errors import ConflictError
from app.modules.users.schemas import ProfileOut, ProfileUpdate

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=ProfileOut, summary="Get my profile and daily goals")
def get_profile(user: CurrentUser):
    return user.profile


@router.patch("", response_model=ProfileOut, summary="Update my profile and daily goals")
def update_profile(body: ProfileUpdate, user: CurrentUser, db: DbSession):
    profile = user.profile
    for field, value in body.changes().items():
        setattr(profile, field, value)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ConflictError("That username is taken") from None
    db.refresh(profile)
    return profile
