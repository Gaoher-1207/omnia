"""Strict validation and context-grounding for goals/streaks model output."""

from datetime import date, datetime
from math import isfinite

from .models import (
    DeadlineAssessment, Goal, GoalConflict, GoalProgress, GoalStatus,
    GoalsStreaksResult, GoalsStreaksStatus, GoalInsight, Streak, StreakStatus,
)


class InvalidGoalsStreaksOutput(ValueError):
    pass


_ROOT = {"status", "goal_summary", "goals", "active_goals", "completed_goals", "goals_needing_attention", "streak_summary", "streaks", "streak_insights", "goal_insights", "goal_conflicts", "suggested_next_focus", "confidence", "uncertainty", "clarification_question"}
_GOAL = {"reference", "title", "domain", "status", "current_value", "target", "progress", "deadline", "priority", "deadline_assessment"}
_STREAK = {"domain", "streak_type", "current_streak", "longest_streak", "status", "last_activity"}
_INSIGHT = {"text", "related_goal", "kind"}
_CONFLICT = {"goal_references", "shared_constraint", "explanation"}
_PRIVATE = ("api_key", "apikey", "password", "credential", "secret", "internal prompt", "system prompt", "database", "infrastructure", "security details")


def _text(value, label, limit=500, optional=False):
    if optional and value is None:
        return None
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise InvalidGoalsStreaksOutput(f"invalid {label}")
    if any(marker in value.casefold() for marker in _PRIVATE):
        raise InvalidGoalsStreaksOutput("output contains private or internal information")
    return value.strip()


def _date(value, label, optional=False):
    if optional and value is None:
        return None
    if not isinstance(value, str):
        raise InvalidGoalsStreaksOutput(f"invalid {label}")
    try:
        if len(value) == 10:
            date.fromisoformat(value)
        else:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if parsed.tzinfo is None or parsed.utcoffset() is None:
                raise ValueError
    except ValueError:
        raise InvalidGoalsStreaksOutput(f"{label} must be an ISO date or timezone-aware datetime") from None
    return value


def _goal_records(context):
    raw = context.get("goals", [])
    if isinstance(raw, dict):
        raw = raw.get("items", [])
    if not isinstance(raw, list):
        raise InvalidGoalsStreaksOutput("selected goals context has invalid structure")
    records = {}
    for row in raw:
        if not isinstance(row, dict):
            raise InvalidGoalsStreaksOutput("selected goal record has invalid structure")
        key = row.get("reference", row.get("id", row.get("title")))
        if isinstance(key, str) and key:
            records[key] = row
        title = row.get("title")
        if isinstance(title, str) and title:
            records.setdefault(title, row)
    return raw, records


def _streak_records(context):
    raw = context.get("streaks", [])
    if isinstance(raw, dict):
        raw = raw.get("items", [])
    if not isinstance(raw, list) or any(not isinstance(row, dict) for row in raw):
        raise InvalidGoalsStreaksOutput("selected streak context has invalid structure")
    return raw


def _numeric(value, label, optional=True):
    if optional and value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) or value < 0 or value > 1_000_000:
        raise InvalidGoalsStreaksOutput(f"invalid {label}")
    return float(value)


def _deadline_assessment(deadline, context):
    time_context = context.get("time_context")
    now = time_context.get("now", time_context.get("current_date")) if isinstance(time_context, dict) else None
    if deadline is None or now is None:
        return DeadlineAssessment.INSUFFICIENT_INFORMATION
    _date(now, "time reference")
    target_day = date.fromisoformat(deadline[:10])
    now_day = date.fromisoformat(now[:10])
    days = (target_day - now_day).days
    return DeadlineAssessment.OVERDUE if days < 0 else DeadlineAssessment.APPROACHING if days <= 3 else DeadlineAssessment.SUFFICIENT_TIME


def validate_goals_streaks_output(raw: dict, *, context) -> GoalsStreaksResult:
    if not isinstance(raw, dict) or set(raw) != _ROOT:
        raise InvalidGoalsStreaksOutput("goals/streaks output has an invalid structure")
    try:
        status = GoalsStreaksStatus(raw["status"])
    except (ValueError, TypeError):
        raise InvalidGoalsStreaksOutput("unsupported result status") from None
    confidence = raw["confidence"]
    if not isinstance(confidence, str) or confidence not in {"low", "medium", "high"}:
        raise InvalidGoalsStreaksOutput("invalid confidence")
    question = _text(raw["clarification_question"], "clarification question", 500, optional=True)
    uncertainty = _text(raw["uncertainty"], "uncertainty", 500, optional=True)
    goals_raw, goal_lookup = _goal_records(context)
    streaks_raw = _streak_records(context)
    goals_out, streaks_out = raw["goals"], raw["streaks"]
    if not isinstance(goals_out, list) or len(goals_out) > 100 or not isinstance(streaks_out, list) or len(streaks_out) > 100:
        raise InvalidGoalsStreaksOutput("invalid goal or streak collection")
    if status is GoalsStreaksStatus.READY:
        if question is not None or raw["goal_summary"] is None and raw["streak_summary"] is None:
            raise InvalidGoalsStreaksOutput("ready response needs a summary and no question")
        goal_summary = _text(raw["goal_summary"], "goal summary", optional=True)
        streak_summary = _text(raw["streak_summary"], "streak summary", optional=True)
    else:
        if not question or raw["goal_summary"] is not None or raw["streak_summary"] is not None or goals_out or streaks_out:
            raise InvalidGoalsStreaksOutput("incomplete response needs a question and no unsupported summaries")
        goal_summary = streak_summary = None
    goals = []
    for item in goals_out:
        if not isinstance(item, dict) or set(item) != _GOAL:
            raise InvalidGoalsStreaksOutput("goal has an invalid structure")
        reference = _text(item["reference"], "goal reference", 128, optional=True)
        title = _text(item["title"], "goal title", 200)
        record = goal_lookup.get(reference or title)
        if record is None or record.get("title") != title:
            raise InvalidGoalsStreaksOutput("goal is not present in selected context")
        expected_reference = record.get("reference", record.get("id"))
        if reference != expected_reference:
            raise InvalidGoalsStreaksOutput("goal reference is not supported by selected context")
        domain = _text(item["domain"], "goal domain", 80, optional=True)
        if domain != record.get("domain"):
            raise InvalidGoalsStreaksOutput("goal domain is not supported by selected context")
        try:
            goal_status = GoalStatus(item["status"])
        except (ValueError, TypeError):
            raise InvalidGoalsStreaksOutput("invalid goal status") from None
        if goal_status.value != record.get("status", "unknown"):
            raise InvalidGoalsStreaksOutput("goal status is not supported by selected context")
        current, target = _numeric(item["current_value"], "current value"), _numeric(item["target"], "target")
        if target == 0 or current != record.get("current_value") or target != record.get("target"):
            raise InvalidGoalsStreaksOutput("goal values are not supported by selected context")
        progress = _numeric(item["progress"], "progress")
        expected_progress = current / target if current is not None and target not in (None, 0) else None
        if progress != expected_progress:
            raise InvalidGoalsStreaksOutput("goal progress must match available current/target values")
        if progress is not None and not 0 <= progress <= 1:
            raise InvalidGoalsStreaksOutput("goal progress must be between 0 and 1")
        deadline = _date(item["deadline"], "deadline", optional=True)
        if deadline != record.get("deadline"):
            raise InvalidGoalsStreaksOutput("goal deadline is not supported by selected context")
        priority = _text(item["priority"], "goal priority", 30, optional=True)
        if priority != record.get("priority"):
            raise InvalidGoalsStreaksOutput("goal priority is not supported by selected context")
        try:
            assessment = DeadlineAssessment(item["deadline_assessment"])
        except (ValueError, TypeError):
            raise InvalidGoalsStreaksOutput("invalid deadline assessment") from None
        if assessment is not _deadline_assessment(deadline, context):
            raise InvalidGoalsStreaksOutput("deadline assessment is unsupported or incorrect")
        goals.append(Goal(reference, title, domain, goal_status, GoalProgress(current, target, progress), deadline, priority, assessment))
    streaks = []
    for item in streaks_out:
        if not isinstance(item, dict) or set(item) != _STREAK:
            raise InvalidGoalsStreaksOutput("streak has an invalid structure")
        domain = _text(item["domain"], "streak domain", 80)
        kind = _text(item["streak_type"], "streak type", 80)
        source = next((r for r in streaks_raw if r.get("domain") == domain and r.get("streak_type", r.get("type")) == kind), None)
        if source is None:
            raise InvalidGoalsStreaksOutput("streak is not present in selected context")
        current = item["current_streak"]
        longest = item["longest_streak"]
        for value, label in ((current, "current streak"), (longest, "longest streak")):
            if value is not None and (isinstance(value, bool) or not isinstance(value, int) or not 0 <= value <= 100_000):
                raise InvalidGoalsStreaksOutput(f"invalid {label}")
        if current != source.get("current_streak") or longest != source.get("longest_streak"):
            raise InvalidGoalsStreaksOutput("streak values are not supported by selected context")
        try:
            streak_status = StreakStatus(item["status"])
        except (ValueError, TypeError):
            raise InvalidGoalsStreaksOutput("invalid streak status") from None
        if streak_status.value != source.get("status", "insufficient_data"):
            raise InvalidGoalsStreaksOutput("streak status is not supported by selected context")
        last = _date(item["last_activity"], "last activity", optional=True)
        if last != source.get("last_activity"):
            raise InvalidGoalsStreaksOutput("last activity is not supported by selected context")
        streaks.append(Streak(domain, kind, current, longest, streak_status, last))
    active = _references(raw["active_goals"], "active goals", goals, allowed={GoalStatus.ACTIVE})
    completed = _references(raw["completed_goals"], "completed goals", goals, allowed={GoalStatus.COMPLETED})
    attention = _references(raw["goals_needing_attention"], "goals needing attention", goals, allowed={GoalStatus.ACTIVE, GoalStatus.PAUSED, GoalStatus.MISSED, GoalStatus.UNKNOWN})
    conflicts_raw = raw["goal_conflicts"]
    if not isinstance(conflicts_raw, list) or len(conflicts_raw) > 20:
        raise InvalidGoalsStreaksOutput("invalid goal conflicts")
    conflicts = []
    available_refs = {g.reference or g.title for g in goals}
    for item in conflicts_raw:
        if not isinstance(item, dict) or set(item) != _CONFLICT:
            raise InvalidGoalsStreaksOutput("goal conflict has an invalid structure")
        refs = item["goal_references"]
        if (not isinstance(refs, list) or len(refs) < 2
                or any(not isinstance(ref, str) or not ref.strip() for ref in refs)
                or len(set(refs)) != len(refs) or not set(refs).issubset(available_refs)):
            raise InvalidGoalsStreaksOutput("conflict references must identify multiple selected goals")
        conflicts.append(GoalConflict(tuple(refs), _text(item["shared_constraint"], "shared constraint"), _text(item["explanation"], "conflict explanation")))
    goals_source = context.get("goals")
    embedded_conflicts = goals_source.get("conflicts", []) if isinstance(goals_source, dict) else []
    if conflicts and not context.get("goal_conflicts") and not embedded_conflicts and not any(isinstance(g, dict) and g.get("shared_constraint") for g in goals_raw):
        raise InvalidGoalsStreaksOutput("goal conflict lacks supporting context")
    for key in ("streak_insights",):
        if not isinstance(raw[key], list) or len(raw[key]) > 20:
            raise InvalidGoalsStreaksOutput(f"invalid {key}")
    streak_insights = tuple(_text(v, "streak insight") for v in raw["streak_insights"])
    goal_insights_raw = raw["goal_insights"]
    if not isinstance(goal_insights_raw, list) or len(goal_insights_raw) > 30:
        raise InvalidGoalsStreaksOutput("invalid goal insights")
    goal_lookup_out = {g.reference or g.title for g in goals}
    goal_insights = []
    for item in goal_insights_raw:
        if not isinstance(item, dict) or set(item) != _INSIGHT:
            raise InvalidGoalsStreaksOutput("goal insight has an invalid structure")
        text = _text(item["text"], "goal insight")
        related = _text(item["related_goal"], "related goal", 128, optional=True)
        if related is not None and related not in goal_lookup_out:
            raise InvalidGoalsStreaksOutput("goal insight references an unsupported goal")
        kind = item["kind"]
        if not isinstance(kind, str) or kind not in {"strength", "attention", "observation"}:
            raise InvalidGoalsStreaksOutput("unsupported goal insight type")
        goal_insights.append(GoalInsight(text, related, kind))
    next_focus = _text(raw["suggested_next_focus"], "suggested next focus", 300, optional=True)
    if status is not GoalsStreaksStatus.READY and (raw["active_goals"] or raw["completed_goals"] or raw["goals_needing_attention"] or raw["streak_insights"] or goal_insights or conflicts or next_focus):
        raise InvalidGoalsStreaksOutput("incomplete response contains unsupported analysis")
    return GoalsStreaksResult(status, goal_summary, tuple(goals), active, completed, attention, streak_summary,
                              tuple(streaks), streak_insights, tuple(goal_insights), tuple(conflicts), next_focus, confidence, uncertainty, question)


def _references(raw, label, goals, allowed):
    if not isinstance(raw, list) or len(raw) > 100:
        raise InvalidGoalsStreaksOutput(f"invalid {label}")
    refs = []
    lookup = {g.reference or g.title: g for g in goals}
    for value in raw:
        ref = _text(value, label, 128)
        if ref not in lookup or lookup[ref].status not in allowed:
            raise InvalidGoalsStreaksOutput(f"{label} contains unsupported goal")
        refs.append(ref)
    return tuple(refs)
