"""Shared FastAPI dependencies: database session and the authenticated user."""

from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.errors import UnauthorizedError
from app.core.security import decode_access_token
from app.db.session import get_db
from app.modules.users.models import User

_bearer = HTTPBearer(auto_error=False)

DbSession = Annotated[Session, Depends(get_db)]


def get_current_user(
    db: DbSession,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise UnauthorizedError()
    decoded = decode_access_token(credentials.credentials)
    if decoded is None:
        raise UnauthorizedError("Your session has expired or is invalid. Please sign in again.")
    user_id, version = decoded
    user = db.get(User, user_id)
    if user is None or user.token_version != version:
        raise UnauthorizedError("Your session has expired or is invalid. Please sign in again.")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]
