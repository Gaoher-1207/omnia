"""Operational events: AI provider latency and fallbacks, replan lifecycle, plan outcomes.

Each event is one structured log line on the `omnia.metrics` logger, for example

    metric event=ai.plan provider=ollama result=fallback reason=timeout latency_ms=30012

so any log pipeline can count and chart them. Counts are also kept in process
for tests and debugging. Values are names and numbers only: never user content,
ids, emails or tokens.
"""

import logging
import threading
import time
from collections import Counter
from collections.abc import Iterator
from contextlib import contextmanager

logger = logging.getLogger("omnia.metrics")

_lock = threading.Lock()
_counts: Counter[tuple] = Counter()


def record(event: str, **fields: object) -> None:
    labels = tuple(sorted((key, str(value)) for key, value in fields.items() if key != "latency_ms"))
    with _lock:
        _counts[(event, labels)] += 1
    logger.info("metric event=%s %s", event, " ".join(f"{key}={value}" for key, value in fields.items()))


@contextmanager
def timer() -> Iterator[dict]:
    """`with timer() as t: ...` then read `t["latency_ms"]`."""
    started = time.perf_counter()
    result: dict = {}
    try:
        yield result
    finally:
        result["latency_ms"] = round((time.perf_counter() - started) * 1000)


def count(event: str, **fields: object) -> int:
    """How many `event`s were recorded whose labels include `fields`."""
    wanted = {(key, str(value)) for key, value in fields.items()}
    with _lock:
        return sum(n for (name, labels), n in _counts.items() if name == event and wanted <= set(labels))


def reset() -> None:
    with _lock:
        _counts.clear()
