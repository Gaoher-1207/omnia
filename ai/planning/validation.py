"""Strict validation for planning model proposals."""

from .models import PlanSession, PlanningResult, PlanStatus


class InvalidPlanningOutput(ValueError):
    pass


def validate_planning_output(raw: dict) -> PlanningResult:
    expected = {"status", "sessions", "assumptions", "uncertainties", "clarification_question"}
    if not isinstance(raw, dict) or set(raw) != expected:
        raise InvalidPlanningOutput("planning output has an invalid structure")
    try:
        status = PlanStatus(raw["status"])
    except (ValueError, TypeError):
        raise InvalidPlanningOutput("unsupported plan status") from None
    sessions, assumptions, uncertainties, question = (raw[k] for k in ("sessions", "assumptions", "uncertainties", "clarification_question"))
    if not isinstance(sessions, list) or len(sessions) > 100:
        raise InvalidPlanningOutput("invalid sessions")
    for values in (assumptions, uncertainties):
        if not isinstance(values, list) or len(values) > 50 or any(not isinstance(v, str) or not v.strip() or len(v) > 500 for v in values):
            raise InvalidPlanningOutput("invalid assumptions or uncertainties")
    if question is not None and (not isinstance(question, str) or not question.strip() or len(question) > 500):
        raise InvalidPlanningOutput("invalid clarification question")
    if status is PlanStatus.PROPOSED and (not sessions or question is not None):
        raise InvalidPlanningOutput("proposed plans need sessions and no question")
    if status is not PlanStatus.PROPOSED and (sessions or not question):
        raise InvalidPlanningOutput("clarification/conflict must have a question and no sessions")
    normalized = []
    expected_session = {"title", "day", "duration_minutes", "break_after_minutes", "priority", "reason"}
    for item in sessions:
        if not isinstance(item, dict) or set(item) != expected_session:
            raise InvalidPlanningOutput("session has an invalid structure")
        title, day, duration, pause, priority, reason = (item[k] for k in ("title", "day", "duration_minutes", "break_after_minutes", "priority", "reason"))
        if not isinstance(title, str) or not title.strip() or len(title) > 200:
            raise InvalidPlanningOutput("session title is invalid")
        if day is not None and (not isinstance(day, str) or not day.strip() or len(day) > 100):
            raise InvalidPlanningOutput("session day is invalid")
        if isinstance(duration, bool) or not isinstance(duration, int) or not 15 <= duration <= 180:
            raise InvalidPlanningOutput("session duration must be 15 to 180 minutes")
        if pause is not None and (isinstance(pause, bool) or not isinstance(pause, int) or not 5 <= pause <= 30):
            raise InvalidPlanningOutput("break duration must be 5 to 30 minutes")
        if duration >= 90 and pause is None:
            raise InvalidPlanningOutput("long sessions need a break")
        if priority not in {"high", "medium", "low"}:
            raise InvalidPlanningOutput("invalid priority")
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 500:
            raise InvalidPlanningOutput("session reason is invalid")
        normalized.append(PlanSession(title.strip(), day, duration, pause, priority, reason.strip()))
    return PlanningResult(status, tuple(normalized), tuple(assumptions), tuple(uncertainties), question)
