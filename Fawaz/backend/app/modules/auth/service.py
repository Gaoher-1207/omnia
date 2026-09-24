from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.errors import AppError, ConflictError, UnauthorizedError
from app.core.security import burn_password_check, hash_password, verify_password
from app.modules.auth.schemas import LoginIn, RegisterIn
from app.modules.users.models import Profile, User


def register(db: Session, data: RegisterIn) -> User:
    if db.scalar(select(User.id).where(User.email == data.email)) is not None:
        raise ConflictError("An account with this email already exists")
    user = User(email=data.email, password_hash=hash_password(data.password))
    user.profile = Profile(display_name=data.display_name, timezone=data.timezone)
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise ConflictError("An account with this email already exists") from None
    db.refresh(user)
    return user


def authenticate(db: Session, data: LoginIn) -> User:
    user = db.scalar(select(User).where(User.email == data.email))
    if user is None:
        burn_password_check()
        raise UnauthorizedError("Incorrect email or password")
    if not verify_password(data.password, user.password_hash):
        raise UnauthorizedError("Incorrect email or password")
    return user


class WrongPasswordError(AppError):
    status_code = 403
    code = "forbidden"


def change_password(db: Session, user: User, current: str, new: str) -> None:
    if not verify_password(current, user.password_hash):
        raise WrongPasswordError("Current password is incorrect")
    user.password_hash = hash_password(new)
    user.token_version += 1
    db.commit()
    db.refresh(user)


def delete_account(db: Session, user: User, password: str) -> None:
    if not verify_password(password, user.password_hash):
        raise WrongPasswordError("Password is incorrect")
    db.delete(user)
    db.commit()
