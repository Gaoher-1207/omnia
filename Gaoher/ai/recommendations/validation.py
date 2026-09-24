"""Strict validation for untrusted model-generated recommendation output."""

from .models import (
    Recommendation, RecommendationPriority, RecommendationResult,
    RecommendationStatus, RecommendationType,
)


class InvalidRecommendationOutput(ValueError):
    pass


MAX_RECOMMENDATIONS = 3
_RESULT_FIELDS = {"status", "recommendations", "confidence", "uncertainty", "clarification_question"}
_ITEM_FIELDS = {"type", "recommendation", "reason", "priority", "expected_benefit", "related_domain", "supporting_context"}
_PRIVATE_MARKERS = ("api_key", "apikey", "password", "credential", "secret", "internal prompt", "system prompt", "database", "infrastructure")


def validate_recommendation_output(raw: dict) -> RecommendationResult:
    if not isinstance(raw, dict) or set(raw) != _RESULT_FIELDS:
        raise InvalidRecommendationOutput("recommendation output has an invalid structure")
    try:
        status = RecommendationStatus(raw["status"])
    except (ValueError, TypeError):
        raise InvalidRecommendationOutput("unsupported recommendation status") from None
    recommendations, confidence = raw["recommendations"], raw["confidence"]
    uncertainty, question = raw["uncertainty"], raw["clarification_question"]
    if not isinstance(recommendations, list) or len(recommendations) > MAX_RECOMMENDATIONS:
        raise InvalidRecommendationOutput("recommendation count exceeds supported limit")
    if not isinstance(confidence, str) or confidence not in {"low", "medium", "high"}:
        raise InvalidRecommendationOutput("invalid confidence")
    for label, value in (("uncertainty", uncertainty), ("clarification question", question)):
        if value is not None and (not isinstance(value, str) or not value.strip() or len(value) > 500):
            raise InvalidRecommendationOutput(f"invalid {label}")
    if status is RecommendationStatus.READY and (not recommendations or question is not None):
        raise InvalidRecommendationOutput("ready result needs recommendations and no question")
    if status is not RecommendationStatus.READY and (recommendations or not question):
        raise InvalidRecommendationOutput("incomplete result needs a clarification question and no recommendations")
    result = []
    for item in recommendations:
        if not isinstance(item, dict) or set(item) != _ITEM_FIELDS:
            raise InvalidRecommendationOutput("recommendation has an invalid structure")
        try:
            kind = RecommendationType(item["type"])
            priority = RecommendationPriority(item["priority"])
        except (ValueError, TypeError):
            raise InvalidRecommendationOutput("unsupported recommendation type or priority") from None
        texts = {}
        for field, maximum in (("recommendation", 400), ("reason", 600), ("expected_benefit", 300)):
            value = item[field]
            if not isinstance(value, str) or not value.strip() or len(value) > maximum:
                raise InvalidRecommendationOutput(f"invalid {field}")
            texts[field] = value.strip()
        domain, support = item["related_domain"], item["supporting_context"]
        if domain is not None and (not isinstance(domain, str) or domain not in {"tasks", "schedule", "exams", "study_progress", "preferences", "recent_plan", "activity", "fitness", "nutrition", "sleep", "goals", "recent_feedback"}):
            raise InvalidRecommendationOutput("unsupported related domain")
        if support is not None and (not isinstance(support, str) or not support.strip() or len(support) > 300):
            raise InvalidRecommendationOutput("invalid supporting context")
        serialized = " ".join([*texts.values(), domain or "", support or ""]).casefold()
        if any(marker in serialized for marker in _PRIVATE_MARKERS):
            raise InvalidRecommendationOutput("recommendation contains private or internal information")
        # The module only emits proposals. Output must not contain action-like commands.
        if any(phrase in texts["recommendation"].casefold() for phrase in ("execute this", "delete the", "create the task", "move the session now", "update your account")):
            raise InvalidRecommendationOutput("recommendation cannot request or claim an executed action")
        result.append(Recommendation(kind, texts["recommendation"], texts["reason"], priority,
                                     texts["expected_benefit"], domain, support))
    if any(not isinstance(v, str) or len(v) > 500 for v in (uncertainty, question) if v is not None):
        raise InvalidRecommendationOutput("invalid result text")
    if any(marker in " ".join(v for v in (uncertainty, question) if v).casefold() for marker in _PRIVATE_MARKERS):
        raise InvalidRecommendationOutput("result contains private or internal information")
    return RecommendationResult(status, tuple(result), confidence, uncertainty, question)
