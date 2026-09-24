"""Deterministic bounded memory selection and non-persistent candidate proposals."""

import re
from dataclasses import replace

from .models import (
    MemoryCandidate, MemoryLifetime, MemorySelectionRequest, MemorySelectionResult,
    MemoryType, Sensitivity,
)
from .validation import validate_candidate, validate_selection_request


MAX_SELECTED_MESSAGES = 8
MAX_SELECTED_MEMORIES = 10
_STOP_WORDS = {"the", "and", "for", "with", "from", "what", "when", "where", "how", "why", "should", "could", "would", "please", "about", "that", "this", "have", "has", "are", "was", "were", "you", "your", "my", "me", "today", "yesterday", "again", "continue"}
_CONTINUITY_CUES = {"continue", "again", "that", "those", "discussed", "before"}


def _terms(text):
    return {word for word in re.findall(r"[a-z0-9]{3,}", text.casefold()) if word not in _STOP_WORDS}


def _score(query_terms, content):
    terms = _terms(content)
    if not query_terms or not terms:
        return 0.0
    return len(query_terms & terms) / len(query_terms)


class ConversationMemoryService:
    """Selects supplied memory only; it has no provider, database, or action interface."""

    def select(self, request: MemorySelectionRequest) -> MemorySelectionResult:
        validate_selection_request(request)
        if request.is_general:
            return MemorySelectionResult(request.user_id, (), None, (), True)
        query_terms = _terms(request.query)
        continuity = bool(set(re.findall(r"[a-z0-9]+", request.query.casefold())) & _CONTINUITY_CUES)
        if not query_terms and not continuity:
            return MemorySelectionResult(request.user_id, (), None, (), False)
        messages = []
        if continuity:
            messages = list(request.messages[-MAX_SELECTED_MESSAGES:])
        else:
            messages = [m for m in request.messages if _score(query_terms, m.content) >= 0.25][-MAX_SELECTED_MESSAGES:]
        summary = request.summary if request.summary and (continuity or _score(query_terms, request.summary.content) >= 0.25) else None
        scored = []
        for memory in request.memories:
            score = _score(query_terms, memory.content)
            if score >= 0.25:
                scored.append((score, memory))
        scored.sort(key=lambda pair: pair[0], reverse=True)
        memories = tuple(replace(memory, relevance=round(score, 3)) for score, memory in scored[:MAX_SELECTED_MEMORIES])
        return MemorySelectionResult(request.user_id, tuple(messages), summary, memories, False)

    @staticmethod
    def propose_candidate(
        *, user_id: str, content: str, memory_type: MemoryType, reason: str,
        confidence: float, sensitivity: Sensitivity = Sensitivity.NON_SENSITIVE,
    ) -> MemoryCandidate:
        """Return a proposal for backend review; this method never persists it."""
        candidate = MemoryCandidate(user_id, content, memory_type, reason, confidence,
                                    MemoryLifetime.PERSISTENT_CANDIDATE, sensitivity)
        validate_candidate(candidate)
        return candidate
