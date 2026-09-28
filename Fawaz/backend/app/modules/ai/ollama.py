"""Shared OmniAI local transport; capabilities own prompts and validation."""

import json

import httpx
from pydantic import BaseModel, ConfigDict, Field

from app.modules.ai.constraints import DEFAULT_TASK_MINUTES, hhmm, minutes, task_deadline, window_start
from app.modules.ai.providers import SYSTEM_PROMPT, ProviderError, RulesProvider
from app.modules.ai.schemas import AIPlanContent, Category, PlanContext


class OllamaTransport:
    """Ollama's native /api/chat, non-streaming, with thinking turned off."""

    name = "ollama"

    def __init__(
        self,
        *,
        base_url: str,
        model: str,
        timeout: float,
        context_tokens: int,
        client: httpx.Client | None = None,
    ):
        self._url = base_url.rstrip("/") + "/api/chat"
        self._model = model
        self._timeout = timeout
        self._context_tokens = context_tokens
        self._client = client

    def complete(self, system: str, messages: list[dict[str, str]], schema: dict | None = None) -> str:
        payload = {
            "model": self._model,
            "stream": False,
            "think": False,
            "keep_alive": "10m",
            "options": {"num_ctx": self._context_tokens, "temperature": 0.3},
            "messages": [{"role": "system", "content": system}, *messages],
        }
        if schema is not None:
            payload["format"] = schema
            payload["options"]["temperature"] = 0
        client = self._client or httpx.Client(timeout=self._timeout)
        try:
            response = client.post(self._url, json=payload, timeout=self._timeout)
        except httpx.TimeoutException:
            raise ProviderError("provider_timeout") from None
        except httpx.HTTPError:
            raise ProviderError("provider_unreachable") from None
        finally:
            if self._client is None:
                client.close()

        if response.status_code == 404:
            raise ProviderError("model_missing")
        if response.status_code >= 500:
            raise ProviderError("provider_unavailable")
        if response.status_code >= 400:
            raise ProviderError("provider_error")
        try:
            content = response.json()["message"]["content"]
        except (ValueError, KeyError, TypeError):
            raise ProviderError("invalid_response") from None
        if not isinstance(content, str):
            raise ProviderError("invalid_response")
        return content


class DurationPlanItem(BaseModel):
    """Transport proposal only; the server calculates end times before validation."""

    model_config = ConfigDict(extra="forbid")
    start: str = Field(pattern=r"^([01][0-9]|2[0-3]):[0-5][0-9]$")
    duration_minutes: int = Field(strict=True, ge=1, le=1440)
    category: Category
    title: str = Field(min_length=1, max_length=120)
    detail: str | None = Field(default=None, max_length=280)
    task_ref: str | None = Field(default=None, max_length=10)
    study_ref: str | None = Field(default=None, max_length=10)

    @property
    def end(self) -> str:
        return hhmm(minutes(self.start) + self.duration_minutes)


class DurationPlanContent(AIPlanContent):
    # Reuse the existing bounded summary/notes and non-overlap validation.
    items: list[DurationPlanItem] = Field(default_factory=list, max_length=20)


class OllamaPlanProvider(OllamaTransport):
    name = "ollama"

    def generate(self, context: PlanContext) -> AIPlanContent:
        # Send derived HH:mm bounds explicitly: the model need not convert minute offsets.
        facts = context.model_dump(mode="json")
        facts["hard_constraints"] = {
            "earliest_start": hhmm(window_start(context)),
            "latest_end": hhmm(context.planning_end_minutes),
            "free_intervals": [
                {"start": hhmm(slot.start_minutes), "end": hhmm(slot.end_minutes)}
                for slot in context.free_intervals
            ] if context.free_intervals is not None else [
                {"start": hhmm(window_start(context)), "end": hhmm(context.planning_end_minutes)}
            ],
            "tasks": [
                {
                    "ref": t.ref,
                    "exact_minutes": t.estimated_minutes or DEFAULT_TASK_MINUTES,
                    "latest_end": hhmm(task_deadline(t, context.planning_end_minutes)),
                }
                for t in context.open_tasks
            ],
        }

        baseline = RulesProvider().generate(context).model_dump()
        baseline["items"] = [
            {
                **{key: value for key, value in item.items() if key != "end"},
                "duration_minutes": minutes(item["end"]) - minutes(item["start"]),
            }
            for item in baseline["items"]
        ]
        # A feasible baseline helps small local models; it never bypasses final validation.
        facts["rules_draft"] = baseline
        facts["output_schema"] = DurationPlanContent.model_json_schema()
        try:
            proposal = DurationPlanContent.model_validate_json(
                self.complete(
                    SYSTEM_PROMPT.split("Reply with only a JSON object")[0]
                    + "Reply only with JSON matching the supplied schema. For each item supply start and "
                    "duration_minutes, not end. Task duration_minutes MUST equal hard_constraints.tasks.exact_minutes. "
                    "Never extend a task to fill a slot. The server calculates end times. "
                    "Use task_ref/study_ref exactly; titles are display labels, never entity identifiers. "
                    "The rules_draft is a feasible starting point. Keep it unless a change improves priorities "
                    "without violating hard constraints. Every block must fit wholly within one "
                    "hard_constraints.free_intervals interval; commitments are fixed busy time. "
                    "Do not change task durations. "
                    "Only explain items actually scheduled.",
                    [{"role": "user", "content": json.dumps(facts)}],
                    DurationPlanContent.model_json_schema(),
                )
            )
            content = proposal.model_dump()
            content["items"] = [
                {**item.model_dump(exclude={"duration_minutes"}), "end": item.end} for item in proposal.items
            ]
            return AIPlanContent.model_validate(content)
        except ValueError:
            raise ProviderError("invalid_response") from None
