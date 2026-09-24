"""Strict output and safety validation for coaching responses."""

from .models import (
    CoachingAction, CoachingInsight, CoachingQuestion, CoachingResult,
    CoachingStatus, CoachingTone,
)


class InvalidCoachingOutput(ValueError):
    pass


_ROOT = {"status", "response", "tone", "domain", "key_insight", "suggested_next_steps", "questions", "confidence", "uncertainty"}
_INSIGHT = {"text", "supporting_reference"}
_ACTION = {"suggestion", "reason", "related_domain"}
_QUESTION = {"question"}
_DOMAINS = {"study", "productivity", "fitness", "nutrition", "goals", "progress", "sleep", "general"}
_PRIVATE = ("api_key", "apikey", "password", "credential", "secret", "internal prompt", "system prompt", "database", "infrastructure", "security details")
_DIAGNOSIS = ("you have depression", "you are depressed", "you have adhd", "you have anxiety disorder", "you are bipolar", "diagnosed with")
_UNSAFE = ("stop taking your medication", "ignore your doctor", "work out through severe pain", "starve yourself", "eat nothing for", "hurt yourself", "kill yourself")
_UNSUPPORTED_PSYCH = ("you are definitely feeling", "you feel this because", "you are lazy", "you failed because you lack")
_ACTION_COMMANDS = ("i moved your", "i changed your", "i created your", "i deleted your", "i updated your schedule", "action executed")


def _text(value, label, limit, *, optional=False):
    if optional and value is None:
        return None
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise InvalidCoachingOutput(f"invalid {label}")
    folded = value.casefold()
    if any(marker in folded for marker in _PRIVATE):
        raise InvalidCoachingOutput("coaching output contains private or internal information")
    if any(marker in folded for marker in _DIAGNOSIS + _UNSAFE + _UNSUPPORTED_PSYCH + _ACTION_COMMANDS):
        raise InvalidCoachingOutput("coaching output violates safety or action boundaries")
    return value.strip()


def validate_coaching_output(raw: dict, *, context) -> CoachingResult:
    if not isinstance(raw, dict) or set(raw) != _ROOT:
        raise InvalidCoachingOutput("coaching output has an invalid structure")
    try:
        status, tone = CoachingStatus(raw["status"]), CoachingTone(raw["tone"])
    except (ValueError, TypeError):
        raise InvalidCoachingOutput("unsupported coaching status or tone") from None
    response = _text(raw["response"], "response", 1600)
    domain = raw["domain"]
    if domain is not None and (not isinstance(domain, str) or domain not in _DOMAINS):
        raise InvalidCoachingOutput("unsupported coaching domain")
    confidence = raw["confidence"]
    if not isinstance(confidence, str) or confidence not in {"low", "medium", "high"}:
        raise InvalidCoachingOutput("invalid confidence")
    uncertainty = _text(raw["uncertainty"], "uncertainty", 500, optional=True)
    if not isinstance(raw["suggested_next_steps"], list) or len(raw["suggested_next_steps"]) > 3:
        raise InvalidCoachingOutput("at most three suggested next steps are allowed")
    if not isinstance(raw["questions"], list) or len(raw["questions"]) > 2:
        raise InvalidCoachingOutput("at most two questions are allowed")
    insight_raw = raw["key_insight"]
    insight = None
    if insight_raw is not None:
        if not isinstance(insight_raw, dict) or set(insight_raw) != _INSIGHT:
            raise InvalidCoachingOutput("key insight has an invalid structure")
        text = _text(insight_raw["text"], "insight", 400)
        reference = insight_raw["supporting_reference"]
        if reference is not None and (not isinstance(reference, str) or reference not in context):
            raise InvalidCoachingOutput("insight reference must name supplied context")
        insight = CoachingInsight(text, reference)
    actions = []
    for item in raw["suggested_next_steps"]:
        if not isinstance(item, dict) or set(item) != _ACTION:
            raise InvalidCoachingOutput("suggested action has an invalid structure")
        suggestion = _text(item["suggestion"], "suggestion", 300)
        reason = _text(item["reason"], "suggestion reason", 300)
        related = item["related_domain"]
        if related is not None and (not isinstance(related, str) or related not in _DOMAINS):
            raise InvalidCoachingOutput("unsupported suggested-action domain")
        actions.append(CoachingAction(suggestion, reason, related))
    questions = []
    for item in raw["questions"]:
        if not isinstance(item, dict) or set(item) != _QUESTION:
            raise InvalidCoachingOutput("question has an invalid structure")
        questions.append(CoachingQuestion(_text(item["question"], "question", 300)))
    if status is CoachingStatus.READY and questions:
        raise InvalidCoachingOutput("ready response cannot include clarification questions")
    if status in {CoachingStatus.CLARIFICATION, CoachingStatus.INSUFFICIENT_CONTEXT} and not questions:
        raise InvalidCoachingOutput("incomplete context response needs a question")
    return CoachingResult(status, response, tone, domain, insight, tuple(actions), tuple(questions), confidence, uncertainty)
