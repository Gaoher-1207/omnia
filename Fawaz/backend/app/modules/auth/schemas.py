import re
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.common.schemas import InputModel, Text
from app.modules.users.schemas import UserOut, check_timezone

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def normalize_email(value: str) -> str:
    value = value.strip().lower()
    if len(value) > 254 or not _EMAIL_RE.match(value):
        raise ValueError("Enter a valid email address")
    return value


class RegisterIn(InputModel):
    email: str
    password: str = Field(min_length=8, max_length=128)
    display_name: Text(60)
    timezone: str = Field(default="UTC", max_length=64)

    _email = field_validator("email")(normalize_email)
    _tz = field_validator("timezone")(check_timezone)


class LoginIn(InputModel):
    email: str
    password: str = Field(min_length=1, max_length=128)

    _email = field_validator("email")(normalize_email)


class ChangePasswordIn(InputModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class DeleteAccountIn(InputModel):
    password: str = Field(min_length=1, max_length=128)


class TokenOut(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int
    user: UserOut
