from fastapi import APIRouter, Request, Response, status

from app.common.deps import CurrentUser, DbSession
from app.core.config import get_settings
from app.core.rate_limit import limiter
from app.core.security import create_access_token
from app.modules.auth import service
from app.modules.auth.schemas import ChangePasswordIn, DeleteAccountIn, LoginIn, RegisterIn, TokenOut
from app.modules.users.models import User
from app.modules.users.schemas import UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _token_response(user: User) -> TokenOut:
    token, expires_in = create_access_token(user.id, user.token_version)
    return TokenOut(access_token=token, expires_in=expires_in, user=UserOut.model_validate(user))


@router.post(
    "/register",
    response_model=TokenOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create an account and sign in",
)
def register(body: RegisterIn, request: Request, db: DbSession):
    limit = get_settings().auth_rate_limit_per_minute
    limiter.hit(f"register:{_client_ip(request)}", limit, 60)
    return _token_response(service.register(db, body))


@router.post("/login", response_model=TokenOut, summary="Sign in with email and password")
def login(body: LoginIn, request: Request, db: DbSession):
    limit = get_settings().auth_rate_limit_per_minute
    limiter.hit(f"login:{_client_ip(request)}:{body.email}", limit, 60)
    return _token_response(service.authenticate(db, body))


@router.get("/me", response_model=UserOut, summary="The signed-in user")
def me(user: CurrentUser):
    return user


@router.post(
    "/delete-account",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Permanently delete my account and all my data",
)
def delete_account(body: DeleteAccountIn, request: Request, user: CurrentUser, db: DbSession):
    limit = get_settings().auth_rate_limit_per_minute
    limiter.hit(f"delete:{user.id}", limit, 60)
    service.delete_account(db, user, body.password)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/change-password", response_model=TokenOut, summary="Change my password (signs out other devices)")
def change_password(body: ChangePasswordIn, user: CurrentUser, db: DbSession):
    limiter.hit(f"password:{user.id}", get_settings().auth_rate_limit_per_minute, 60)
    service.change_password(db, user, body.current_password, body.new_password)
    return _token_response(user)


@router.post(
    "/logout-all",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Sign out everywhere (every existing token stops working)",
)
def logout_all(user: CurrentUser, db: DbSession):
    user.token_version += 1
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
