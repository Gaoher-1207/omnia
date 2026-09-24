"""One error shape for every failure: {"error": {"code", "message", "details"?, "request_id"}}.

Clients never see stack traces, SQL, or the values they submitted echoed back.
"""

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("omnia.errors")

_STATUS_CODES = {
    400: "bad_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    409: "conflict",
    413: "payload_too_large",
    415: "unsupported_media_type",
    422: "validation_error",
    429: "rate_limited",
    502: "upstream_error",
    503: "service_unavailable",
}


class AppError(Exception):
    status_code = 400
    code = "bad_request"

    def __init__(self, message: str, *, details: Any = None, headers: dict[str, str] | None = None):
        super().__init__(message)
        self.message = message
        self.details = details
        self.headers = headers


class NotFoundError(AppError):
    status_code = 404
    code = "not_found"

    def __init__(self, resource: str = "Resource"):
        super().__init__(f"{resource} not found")


class ConflictError(AppError):
    status_code = 409
    code = "conflict"


class UnauthorizedError(AppError):
    status_code = 401
    code = "unauthorized"

    def __init__(self, message: str = "Authentication required"):
        super().__init__(message, headers={"WWW-Authenticate": "Bearer"})


class RateLimitedError(AppError):
    status_code = 429
    code = "rate_limited"

    def __init__(self, retry_after: int):
        super().__init__(
            "Too many requests. Please wait and try again.",
            headers={"Retry-After": str(retry_after)},
        )


def _body(request: Request, code: str, message: str, details: Any = None) -> dict:
    error: dict[str, Any] = {"code": code, "message": message}
    if details is not None:
        error["details"] = details
    request_id = getattr(request.state, "request_id", None)
    if request_id:
        error["request_id"] = request_id
    return {"error": error}


def _field_path(loc: tuple) -> str:
    return ".".join(str(part) for part in loc)


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def _app_error(request: Request, exc: AppError):
        return JSONResponse(
            _body(request, exc.code, exc.message, exc.details),
            status_code=exc.status_code,
            headers=exc.headers,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(request: Request, exc: StarletteHTTPException):
        code = _STATUS_CODES.get(exc.status_code, "error")
        message = exc.detail if isinstance(exc.detail, str) else code.replace("_", " ").capitalize()
        return JSONResponse(
            _body(request, code, message),
            status_code=exc.status_code,
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def _validation_error(request: Request, exc: RequestValidationError):
        details = [
            {"field": _field_path(err.get("loc", ())), "message": err.get("msg", "Invalid value")}
            for err in exc.errors()
        ]
        return JSONResponse(
            _body(request, "validation_error", "Some fields are invalid", details),
            status_code=422,
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception):
        logger.exception(
            "Unhandled error on %s %s (request_id=%s)",
            request.method,
            request.url.path,
            getattr(request.state, "request_id", "-"),
        )
        return JSONResponse(
            _body(request, "internal_error", "Something went wrong. Please try again."),
            status_code=500,
        )
