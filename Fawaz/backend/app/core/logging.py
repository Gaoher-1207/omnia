"""Logging and request IDs.

Access logs record method, path, status, duration and request id only. Never log
request bodies, passwords, tokens, or health/food data.
"""

import json
import logging
import re
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

access_logger = logging.getLogger("omnia.access")
# Secret calendar links carry a token in the path; never write it to logs.
_SECRET_PATH = re.compile(r"^(/api/integrations/calendar/)[^/]+(\.ics)$")


def _loggable(path: str) -> str:
    return _SECRET_PATH.sub(r"\1<redacted>\2", path)


def configure_logging(level: str) -> None:
    logging.basicConfig(
        level=level.upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    # httpx logs full request URLs at INFO; keep it quiet so URLs never land in logs.
    logging.getLogger("httpx").setLevel(logging.WARNING)


class RequestContextMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, *, max_body_bytes: int, production: bool = False):
        super().__init__(app)
        self.max_body_bytes = max_body_bytes
        self.production = production

    async def dispatch(self, request: Request, call_next):
        incoming = request.headers.get("x-request-id", "")
        request_id = incoming if 0 < len(incoming) <= 64 and incoming.isascii() else uuid.uuid4().hex
        request.state.request_id = request_id
        started = time.perf_counter()
        length = request.headers.get("content-length", "")
        if length.isdigit() and int(length) > self.max_body_bytes:
            body = {"error": {"code": "payload_too_large", "message": "Request is too large", "request_id": request_id}}
            response = Response(json.dumps(body), status_code=413, media_type="application/json")
        else:
            response = await call_next(request)
        duration_ms = (time.perf_counter() - started) * 1000
        response.headers["X-Request-ID"] = request_id
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("X-Frame-Options", "DENY")
        if self.production:
            response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        access_logger.info(
            "%s %s %s %.1fms rid=%s",
            request.method,
            _loggable(request.url.path),
            response.status_code,
            duration_ms,
            request_id,
        )
        return response
