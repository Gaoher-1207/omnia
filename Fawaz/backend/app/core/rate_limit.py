"""A small in-memory sliding-window rate limiter.

Good enough for a single backend instance. When OMNIA runs more than one instance,
swap the storage for Redis (or the gateway's limiter) behind the same interface.
"""

import math
import threading
import time
from collections import defaultdict, deque

from app.core.errors import RateLimitedError


class RateLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str, limit: int, window_seconds: int) -> None:
        """Record one attempt for `key`; raise RateLimitedError if over the limit."""
        now = time.monotonic()
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= now - window_seconds:
                hits.popleft()
            if len(hits) >= limit:
                retry_after = math.ceil(hits[0] + window_seconds - now)
                raise RateLimitedError(max(retry_after, 1))
            hits.append(now)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


limiter = RateLimiter()
