"""Strict progress response validation and evidence-aware trend safeguards."""

from collections.abc import Mapping
from math import isfinite

from .models import ProgressArea, ProgressMetric, ProgressResult, ProgressStatus, ProgressSummary, ProgressTrend


class InvalidProgressOutput(ValueError):
    pass


_ROOT = {"status", "summary", "completed_items", "metrics", "areas", "strengths", "attention_areas", "trends", "blockers", "suggested_next_focus", "confidence", "uncertainty", "clarification_question"}
_METRIC = {"name", "completed", "total", "completion_rate"}
_AREA = {"domain", "summary", "metrics", "trend"}
_DOMAINS = {"study", "productivity", "fitness", "nutrition", "goals", "general_progress"}
_PRIVATE = ("api_key", "apikey", "password", "credential", "secret", "internal prompt", "system prompt", "database", "infrastructure")


def has_comparable_periods(context) -> bool:
    """Return true only when selected context explicitly contains multi-period data."""
    def walk(value):
        if isinstance(value, Mapping):
            for key, nested in value.items():
                normalized = str(key).casefold()
                if isinstance(nested, (list, tuple)) and len(nested) >= 2 and any(tag in normalized for tag in ("history", "period", "comparison", "previous", "prior")):
                    return True
                if walk(nested):
                    return True
        elif isinstance(value, (list, tuple)):
            return any(walk(item) for item in value)
        return False
    return walk(context)


def _text(value, label, max_length=600, optional=False):
    if optional and value is None:
        return None
    if not isinstance(value, str) or not value.strip() or len(value) > max_length:
        raise InvalidProgressOutput(f"invalid {label}")
    if any(marker in value.casefold() for marker in _PRIVATE):
        raise InvalidProgressOutput("progress output contains private or internal information")
    return value.strip()


def _metric(raw):
    if not isinstance(raw, dict) or set(raw) != _METRIC:
        raise InvalidProgressOutput("metric has an invalid structure")
    name = _text(raw["name"], "metric name", 100)
    completed, total, rate = raw["completed"], raw["total"], raw["completion_rate"]
    values = []
    for value in (completed, total):
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) or value < 0 or value > 1_000_000):
            raise InvalidProgressOutput("metric values must be finite, non-negative, and bounded")
        values.append(None if value is None else float(value))
    completed, total = values
    if completed is not None and total is not None and completed > total:
        raise InvalidProgressOutput("completed metric cannot exceed total")
    calculated = completed / total if completed is not None and total not in (None, 0) else None
    if rate is not None and (isinstance(rate, bool) or not isinstance(rate, (int, float)) or not isfinite(rate) or not 0 <= rate <= 1):
        raise InvalidProgressOutput("completion_rate must be between 0 and 1")
    if rate is not None and calculated is None:
        raise InvalidProgressOutput("completion_rate requires completed and nonzero total")
    if rate is not None and abs(float(rate) - calculated) > 0.005:
        raise InvalidProgressOutput("completion_rate conflicts with completed/total values")
    return ProgressMetric(name, completed, total, calculated if rate is None else float(rate))


def validate_progress_output(raw: dict, *, context) -> ProgressResult:
    if not isinstance(raw, dict) or set(raw) != _ROOT:
        raise InvalidProgressOutput("progress output has an invalid structure")
    try:
        status = ProgressStatus(raw["status"])
    except (ValueError, TypeError):
        raise InvalidProgressOutput("unsupported progress status") from None
    confidence = raw["confidence"]
    if not isinstance(confidence, str) or confidence not in {"low", "medium", "high"}:
        raise InvalidProgressOutput("invalid confidence")
    question = _text(raw["clarification_question"], "clarification question", 500, optional=True)
    uncertainty = _text(raw["uncertainty"], "uncertainty", 500, optional=True)
    if status is ProgressStatus.READY:
        if question is not None or not isinstance(raw["summary"], dict) or set(raw["summary"]) != {"fact", "interpretation"}:
            raise InvalidProgressOutput("ready result requires a summary and no question")
        summary = ProgressSummary(_text(raw["summary"]["fact"], "summary fact"), _text(raw["summary"]["interpretation"], "summary interpretation", optional=True))
    else:
        if not question or raw["summary"] is not None:
            raise InvalidProgressOutput("incomplete result requires a question and no summary")
        summary = None
    completed_items = raw["completed_items"]
    if not isinstance(completed_items, list) or len(completed_items) > 100:
        raise InvalidProgressOutput("invalid completed items")
    completed_items = tuple(_text(item, "completed item", 200) for item in completed_items)
    metric_values = raw["metrics"]
    area_values = raw["areas"]
    if not isinstance(metric_values, list) or len(metric_values) > 50 or not isinstance(area_values, list) or len(area_values) > 20:
        raise InvalidProgressOutput("invalid metrics or areas")
    metrics = tuple(_metric(m) for m in metric_values)
    areas = []
    for area in area_values:
        if not isinstance(area, dict) or set(area) != _AREA or not isinstance(area["domain"], str) or area["domain"] not in _DOMAINS:
            raise InvalidProgressOutput("unsupported progress area")
        try:
            trend = ProgressTrend(area["trend"])
        except (ValueError, TypeError):
            raise InvalidProgressOutput("unsupported trend") from None
        area_metrics = area["metrics"]
        if not isinstance(area_metrics, list) or len(area_metrics) > 50:
            raise InvalidProgressOutput("invalid area metrics")
        areas.append(ProgressArea(area["domain"], _text(area["summary"], "area summary"), tuple(_metric(m) for m in area_metrics), trend))
    trends_raw = raw["trends"]
    if not isinstance(trends_raw, list) or len(trends_raw) > 10:
        raise InvalidProgressOutput("invalid trends")
    try:
        trends = tuple(ProgressTrend(v) for v in trends_raw)
    except (ValueError, TypeError):
        raise InvalidProgressOutput("unsupported trend") from None
    if not has_comparable_periods(context) and (any(t is not ProgressTrend.INSUFFICIENT_DATA for t in trends) or any(a.trend is not ProgressTrend.INSUFFICIENT_DATA for a in areas)):
        raise InvalidProgressOutput("trend claims require comparable periods in selected context")
    if status is not ProgressStatus.READY and (completed_items or metrics or areas or trends):
        raise InvalidProgressOutput("incomplete result cannot contain unsupported progress claims")
    for key in ("strengths", "attention_areas", "blockers"):
        if not isinstance(raw[key], list) or len(raw[key]) > 20:
            raise InvalidProgressOutput(f"invalid {key}")
    strengths = tuple(_text(v, "strength", 300) for v in raw["strengths"])
    attention = tuple(_text(v, "attention area", 300) for v in raw["attention_areas"])
    blockers = tuple(_text(v, "blocker", 300) for v in raw["blockers"])
    next_focus = _text(raw["suggested_next_focus"], "suggested next focus", 300, optional=True)
    return ProgressResult(status, summary, completed_items, metrics, tuple(areas), strengths, attention, trends,
                          blockers, next_focus, confidence, uncertainty, question)
