"""The compact edit protocol the AI models use for replanning.

Measured on the local demo setup (qwen3:8b on an RTX 4060), asking the model to
rewrite the *whole* schedule took 21–39 s per request, and about one answer in
three failed deterministic validation, mostly because unchanged blocks came
back altered (a task's length, an overlap). Here the model returns only what
changes, by short keys:

    {"summary": "...", "changes": [
        {"action": "move",   "key": "i3", "start": "15:00"},
        {"action": "resize", "key": "i5", "start": "16:00", "end": "16:30"},
        {"action": "remove", "key": "i6"},
        {"action": "add", "start": "19:00", "end": "19:45", "category": "study",
         "title": "Revision", "study_ref": "b1"}]}

The server copies every untouched block exactly and builds the full schedule
itself, so a model can't alter unrelated blocks, invent entity ids (it only
ever sees refs like `t1`/`b1`, which the server maps back), or skip a block by
accident. The rebuilt schedule then goes through the same authoritative
validation as before. Anything ambiguous (an unknown key, a block edited
twice, a past block) is rejected, never guessed.
"""

import json
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.modules.ai.constraints import hhmm, minutes
from app.modules.ai.schemas import Category, PlanItem, ReplanDraft

_HHMM = r"^([01][0-9]|2[0-3]):[0-5][0-9]$"


class EditProtocolError(ValueError):
    """The model's answer can't be turned into a schedule. `code` is safe to log."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class Change(BaseModel):
    # Unknown extra keys (a "reason", say) are dropped, not trusted.
    model_config = ConfigDict(extra="ignore")
    action: Literal["move", "resize", "remove", "add"]
    key: str | None = Field(default=None, max_length=8)
    start: str | None = Field(default=None, pattern=_HHMM)
    end: str | None = Field(default=None, pattern=_HHMM)
    category: Category | None = None
    title: str | None = Field(default=None, min_length=1, max_length=120)
    task_ref: str | None = Field(default=None, max_length=10)
    study_ref: str | None = Field(default=None, max_length=10)


class EditDraft(BaseModel):
    model_config = ConfigDict(extra="ignore")
    summary: str = Field(min_length=1, max_length=280)
    explanation: str = Field(default="", max_length=1000)
    changes: list[Change] = Field(default_factory=list, max_length=20)


# Flat (no $ref) so local grammar-constrained decoding handles it.
EDIT_SCHEMA = {
    "type": "object",
    "properties": {
        "summary": {"type": "string", "maxLength": 160},
        "explanation": {"type": "string", "maxLength": 300},
        "changes": {
            "type": "array",
            "maxItems": 12,
            "items": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["move", "resize", "remove", "add"]},
                    "key": {"type": ["string", "null"]},
                    "start": {"type": ["string", "null"]},
                    "end": {"type": ["string", "null"]},
                    "category": {
                        "type": ["string", "null"],
                        "enum": ["study", "task", "fitness", "break", "recovery", "other", None],
                    },
                    "title": {"type": ["string", "null"]},
                    "task_ref": {"type": ["string", "null"]},
                    "study_ref": {"type": ["string", "null"]},
                },
                "required": ["action"],
            },
        },
    },
    "required": ["summary", "changes"],
}

SYSTEM_PROMPT = (
    "You adjust today's schedule in Omnia, a planning app. Reply with ONE JSON object only, no prose, no code "
    'fences: {"summary": short sentence, "explanation": one or two short sentences, "changes": [...]}. '
    "List ONLY the blocks that change; untouched blocks stay exactly as they are. Each change is one of: "
    '{"action":"move","key":"i3","start":"HH:MM"} keeps the length; '
    '{"action":"resize","key":"i3","start":"HH:MM","end":"HH:MM"}; '
    '{"action":"remove","key":"i3"}; '
    '{"action":"add","start":"HH:MM","end":"HH:MM","category":"task|study|fitness|break|recovery|other",'
    '"title":"...","task_ref":"t1 or null","study_ref":"b1 or null"}. '
    "Use only keys from `schedule` and refs from `tasks`/`study`; never invent ids. Blocks marked past can't "
    "change. Every block must fit inside one free interval, must not overlap another block, and must start at or "
    "after `now`. A task keeps its exact minutes. A study block is at most 60 minutes. If nothing should change, "
    'return "changes": [].'
)


def parse_json_object(text: str) -> dict:
    """The first complete JSON object in `text`: tolerates ```json fences and prose around
    it. A cut-off (partial) object is an error, never patched."""
    if not isinstance(text, str):
        raise EditProtocolError("not_text")
    start = text.find("{")
    if start == -1:
        raise EditProtocolError("no_json_object")
    depth, in_string, escaped = 0, False, False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                try:
                    value = json.loads(text[start : index + 1])
                except json.JSONDecodeError:
                    raise EditProtocolError("malformed_json") from None
                if not isinstance(value, dict):
                    raise EditProtocolError("not_an_object")
                return value
    raise EditProtocolError("truncated_json")


def keyed_schedule(payload: dict) -> list[tuple[str, dict]]:
    """Short keys (i1, i2…) for the current schedule, in order."""
    return [(f"i{index}", item) for index, item in enumerate(payload["current_schedule"], start=1)]


def prompt_facts(payload: dict) -> dict:
    """Only what the model needs to edit the schedule; no names, emails or ids."""
    context = payload["context"]
    earliest = payload["hard_constraints"]["earliest_start"]
    return {
        "request": payload["request"],
        "now": earliest,
        "day_ends": payload["hard_constraints"]["latest_end"],
        "free_intervals": [
            {"start": hhmm(slot["start_minutes"]), "end": hhmm(slot["end_minutes"])}
            for slot in payload["hard_constraints"]["free_intervals"]
        ]
        or [{"start": earliest, "end": payload["hard_constraints"]["latest_end"]}],
        "schedule": [
            {
                "key": key,
                "start": item["start"],
                "end": item["end"],
                "category": item["category"],
                "title": item["title"],
                **({"task_ref": item["task_ref"]} if item.get("task_ref") else {}),
                **({"study_ref": item["study_ref"]} if item.get("study_ref") else {}),
                **({"past": True} if minutes(item["start"]) < minutes(earliest) else {}),
            }
            for key, item in keyed_schedule(payload)
        ],
        "tasks": [
            {"ref": task["ref"], "title": task["title"], "minutes": task.get("estimated_minutes") or 30}
            for task in context.get("open_tasks", [])
        ],
        "study": [
            {"ref": block["ref"], "title": f"{block['subject']}: {block['title']}", "budget_minutes": block["minutes"]}
            for block in context.get("study_blocks", [])
        ],
        "done_today": [outcome["title"] for outcome in context.get("plan_outcomes", []) if outcome["status"] == "done"],
        "last_night_sleep_minutes": (context.get("last_night_sleep") or {}).get("minutes"),
    }


def user_message(payload: dict, feedback: str | None = None) -> str:
    message = json.dumps(prompt_facts(payload), separators=(",", ":"))
    if feedback:
        message += f"\nYour previous answer was rejected ({feedback}). Fix that and reply with the JSON object only."
    return message


def to_draft(raw: str | dict, payload: dict) -> ReplanDraft:
    """Parse the model's answer and rebuild the full proposed schedule from it."""
    try:
        edits = EditDraft.model_validate(raw if isinstance(raw, dict) else parse_json_object(raw))
    except ValidationError:
        raise EditProtocolError("schema_mismatch") from None
    now = minutes(payload["hard_constraints"]["earliest_start"])
    blocks = dict(keyed_schedule(payload))
    future = {key: dict(item) for key, item in blocks.items() if minutes(item["start"]) >= now}
    touched: set[str] = set()
    added: list[dict] = []
    for change in edits.changes:
        if change.action == "add":
            if change.start is None or change.end is None or change.category is None or change.title is None:
                raise EditProtocolError("incomplete_add")
            added.append(
                {
                    "start": change.start,
                    "end": change.end,
                    "category": change.category,
                    "title": change.title,
                    "detail": None,
                    "task_ref": change.task_ref,
                    "study_ref": change.study_ref,
                }
            )
            continue
        key = change.key
        if key not in blocks:
            raise EditProtocolError("unknown_key")
        if key not in future:
            raise EditProtocolError("past_block_edited")
        if key in touched:
            raise EditProtocolError("conflicting_changes")
        touched.add(key)
        item = future[key]
        if change.action == "remove":
            del future[key]
        elif change.action == "move":
            if change.start is None:
                raise EditProtocolError("incomplete_move")
            length = minutes(item["end"]) - minutes(item["start"])
            item["start"] = change.start
            item["end"] = change.end or hhmm(minutes(change.start) + length)
        else:  # resize
            if change.start is None and change.end is None:
                raise EditProtocolError("incomplete_resize")
            item["start"] = change.start or item["start"]
            item["end"] = change.end or item["end"]
    rows = [
        {key: item.get(key) for key in ("start", "end", "category", "title", "detail", "task_ref", "study_ref")}
        for item in future.values()
    ] + added
    try:
        items = [PlanItem.model_validate(row) for row in rows]
        return ReplanDraft(
            summary=edits.summary.strip()[:280],
            explanation=(edits.explanation.strip() or edits.summary.strip())[:1000],
            items=items,
        )
    except ValidationError:
        raise EditProtocolError("invalid_block") from None
