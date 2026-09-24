"""Password hashing and access tokens.

Passwords are hashed with scrypt (Python standard library, memory-hard, OWASP-listed)
so the MVP needs no native crypto dependency. Tokens are short JWTs signed with
AUTH_SECRET (HS256). Both choices are up for review by the security contributors.
"""

import base64
import hashlib
import hmac
import logging
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import get_settings

logger = logging.getLogger(__name__)

_SCRYPT_R = 8
_SCRYPT_P = 1
_SCRYPT_DKLEN = 32
_JWT_ALGORITHM = "HS256"
_ephemeral_secret: str | None = None


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def hash_password(password: str) -> str:
    n = get_settings().password_hash_n
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode(),
        salt=salt,
        n=n,
        r=_SCRYPT_R,
        p=_SCRYPT_P,
        dklen=_SCRYPT_DKLEN,
        maxmem=256 * 1024 * 1024,
    )
    return f"scrypt${n}${_SCRYPT_R}${_SCRYPT_P}${_b64(salt)}${_b64(digest)}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, n, r, p, salt, expected = stored.split("$")
        if algo != "scrypt":
            return False
        digest = hashlib.scrypt(
            password.encode(),
            salt=_unb64(salt),
            n=int(n),
            r=int(r),
            p=int(p),
            dklen=len(_unb64(expected)),
            maxmem=256 * 1024 * 1024,
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(digest, _unb64(expected))


_DUMMY_HASH: str | None = None


def burn_password_check() -> None:
    """Spend the same time as a real check so login timing doesn't reveal which emails exist."""
    global _DUMMY_HASH
    if _DUMMY_HASH is None:
        _DUMMY_HASH = hash_password(secrets.token_hex(8))
    verify_password("not-the-password", _DUMMY_HASH)


def _signing_secret() -> str:
    global _ephemeral_secret
    secret = get_settings().auth_secret
    if secret:
        return secret
    if _ephemeral_secret is None:
        logger.warning("AUTH_SECRET is not set; using a temporary secret. Tokens reset on restart.")
        _ephemeral_secret = secrets.token_urlsafe(48)
    return _ephemeral_secret


def create_access_token(user_id: uuid.UUID, version: int = 0) -> tuple[str, int]:
    minutes = get_settings().access_token_expire_minutes
    now = datetime.now(UTC)
    payload = {
        "sub": str(user_id),
        "ver": version,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=minutes),
    }
    return jwt.encode(payload, _signing_secret(), algorithm=_JWT_ALGORITHM), minutes * 60


def decode_access_token(token: str) -> tuple[uuid.UUID, int] | None:
    """Return (user id, token version) for a valid token, else None."""
    try:
        payload = jwt.decode(
            token,
            _signing_secret(),
            algorithms=[_JWT_ALGORITHM],
            options={"require": ["sub", "exp", "iat"]},
        )
        if payload.get("type") != "access":
            return None
        return uuid.UUID(payload["sub"]), int(payload.get("ver", 0))
    except (jwt.PyJWTError, ValueError, KeyError, TypeError):
        return None
