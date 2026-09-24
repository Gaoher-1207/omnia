"""Bounded structural and sensitivity validation for memory objects."""

import json
import re
from datetime import datetime
from math import isfinite

from .models import (
    ConversationMessage, ConversationSummary, MemoryCandidate, MemoryItem,
    MemoryLifetime, MemorySelectionRequest, MemoryType, Sensitivity,
)


class InvalidMemory(ValueError):
    pass


MAX_MESSAGES = 12
MAX_MESSAGE_LENGTH = 4000
MAX_SUMMARY_LENGTH = 1200
MAX_MEMORIES = 20
MAX_MEMORY_LENGTH = 1200
MAX_MEMORY_BYTES = 24_000
MAX_CANDIDATE_LENGTH = 600
_ROLES = {"user", "assistant"}
_SENSITIVE_TERMS = (
    "diabetes", "cancer", "hiv", "mental health", "depression", "depressed", "bipolar", "schizophrenia",
    "religion", "christian", "muslim", "hindu", "jewish", "buddhist", "atheist",
    "political affiliation", "vote for", "political party", "sexual orientation", "gay", "lesbian", "bisexual", "transgender", "sex life",
    "race", "ethnicity", "criminal history", "criminal record", "convicted",
)
_SECRET_PATTERNS = (
    re.compile(r"\b(?:password|api[_ -]?key|access[_ -]?token|secret[_ -]?key|credential)\s*[:=]\s*\S+", re.I),
    re.compile(r"\b\d{1,6}\s+[\w.-]+\s+(?:street|st|road|rd|avenue|ave|boulevard|blvd)\b", re.I),
    re.compile(r"\b-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}\b"),
    re.compile(r"\b(?:bank account|routing number|credit card)\s*(?:number)?\s*[:=]?\s*\d{6,}", re.I),
)
_INTERNAL_TERMS = ("internal prompt", "system prompt", "database schema", "infrastructure", "security configuration")


def validate_user_id(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 256:
        raise InvalidMemory("memory owner identity is invalid")


def validate_timestamp(value):
    if value is not None and (not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None):
        raise InvalidMemory("timestamps must be timezone-aware datetimes")


def validate_safe_content(value, label, limit):
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise InvalidMemory(f"{label} is empty or exceeds its length limit")
    lowered = value.casefold()
    if any(term in lowered for term in _SENSITIVE_TERMS) or any(pattern.search(value) for pattern in _SECRET_PATTERNS):
        raise InvalidMemory("sensitive personal or credential information cannot be memory")
    if any(term in lowered for term in _INTERNAL_TERMS):
        raise InvalidMemory("internal application information cannot be memory")


def validate_probability(value, label):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not isfinite(value) or not 0 <= value <= 1:
        raise InvalidMemory(f"{label} must be between 0 and 1")


def validate_message(message: ConversationMessage, user_id: str):
    if not isinstance(message, ConversationMessage):
        raise InvalidMemory("history contains an invalid message")
    validate_user_id(message.user_id)
    if message.user_id != user_id:
        raise InvalidMemory("history belongs to another user")
    if not isinstance(message.role, str) or message.role not in _ROLES:
        raise InvalidMemory("unsupported conversation role")
    validate_safe_content(message.content, "message", MAX_MESSAGE_LENGTH)
    validate_timestamp(message.timestamp)


def validate_summary(summary: ConversationSummary | None, user_id: str):
    if summary is None:
        return
    if not isinstance(summary, ConversationSummary) or summary.user_id != user_id:
        raise InvalidMemory("summary is invalid or belongs to another user")
    validate_safe_content(summary.content, "summary", MAX_SUMMARY_LENGTH)
    if not isinstance(summary.lifetime, MemoryLifetime) or summary.lifetime not in {MemoryLifetime.REQUEST, MemoryLifetime.SESSION}:
        raise InvalidMemory("summary lifetime must be request or session scoped")


def validate_memory(memory: MemoryItem, user_id: str):
    if not isinstance(memory, MemoryItem) or memory.user_id != user_id:
        raise InvalidMemory("memory is invalid or belongs to another user")
    validate_safe_content(memory.content, "memory", MAX_MEMORY_LENGTH)
    if not isinstance(memory.memory_type, MemoryType) or memory.memory_type is MemoryType.SUMMARY:
        raise InvalidMemory("memory type is invalid")
    if memory.memory_type is MemoryType.PREFERENCE and not memory.explicitly_provided:
        raise InvalidMemory("preferences must be explicitly supplied")
    if not isinstance(memory.lifetime, MemoryLifetime) or memory.lifetime not in {MemoryLifetime.REQUEST, MemoryLifetime.SESSION}:
        raise InvalidMemory("stored memory lifetime must be request or session scoped")
    validate_probability(memory.confidence, "confidence")
    validate_probability(memory.relevance, "relevance")


def validate_selection_request(request: MemorySelectionRequest):
    if not isinstance(request, MemorySelectionRequest):
        raise InvalidMemory("request must be a MemorySelectionRequest")
    validate_user_id(request.user_id)
    if not isinstance(request.query, str) or not request.query.strip() or len(request.query) > MAX_MESSAGE_LENGTH:
        raise InvalidMemory("query is empty or exceeds its length limit")
    if not isinstance(request.is_general, bool):
        raise InvalidMemory("is_general must be boolean")
    if not isinstance(request.messages, (tuple, list)) or len(request.messages) > MAX_MESSAGES:
        raise InvalidMemory("conversation history exceeds the message limit")
    if not isinstance(request.memories, (tuple, list)) or len(request.memories) > MAX_MEMORIES:
        raise InvalidMemory("memory count exceeds the supported limit")
    for message in request.messages:
        validate_message(message, request.user_id)
    validate_summary(request.summary, request.user_id)
    for memory in request.memories:
        validate_memory(memory, request.user_id)
    size_candidate = {
        "query": request.query,
        "messages": [{"role": m.role, "content": m.content, "timestamp": m.timestamp.isoformat() if m.timestamp else None} for m in request.messages],
        "summary": request.summary.content if request.summary else None,
        "memories": [m.content for m in request.memories],
    }
    try:
        size = len(json.dumps(size_candidate, ensure_ascii=False, allow_nan=False).encode("utf-8"))
    except (TypeError, ValueError):
        raise InvalidMemory("memory payload is not valid JSON") from None
    if size > MAX_MEMORY_BYTES:
        raise InvalidMemory("total memory input exceeds size limit")


def validate_candidate(candidate: MemoryCandidate):
    if not isinstance(candidate, MemoryCandidate):
        raise InvalidMemory("candidate must be a MemoryCandidate")
    validate_user_id(candidate.user_id)
    validate_safe_content(candidate.content, "candidate", MAX_CANDIDATE_LENGTH)
    validate_safe_content(candidate.reason, "candidate reason", 300)
    if not isinstance(candidate.memory_type, MemoryType) or candidate.memory_type is MemoryType.CONVERSATION:
        raise InvalidMemory("unsupported candidate memory type")
    if not isinstance(candidate.suggested_lifetime, MemoryLifetime) or candidate.suggested_lifetime is not MemoryLifetime.PERSISTENT_CANDIDATE:
        raise InvalidMemory("candidate lifetime must be persistent_candidate")
    if not isinstance(candidate.sensitivity, Sensitivity) or candidate.sensitivity is not Sensitivity.NON_SENSITIVE:
        raise InvalidMemory("sensitive or personal content cannot be proposed for persistent memory")
    validate_probability(candidate.confidence, "candidate confidence")
