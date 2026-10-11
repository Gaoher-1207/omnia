"""OpenRouter daily-plan provider: strict parse; service owns final validation."""

import httpx
from pydantic import ValidationError

from app.modules.ai import replan_protocol
from app.modules.ai.openrouter_client import OpenRouterClient
from app.modules.ai.providers import SYSTEM_PROMPT, ProviderError
from app.modules.ai.schemas import AIPlanContent, PlanContext, ReplanDraft


class OpenRouterPlanProvider:
    name = "openrouter"

    def __init__(
        self,
        *,
        api_key: str,
        primary_model: str,
        fallback_model: str,
        timeout: float,
        client: httpx.Client | None = None,
        openrouter_client: OpenRouterClient | None = None,
    ):
        self.primary_model = primary_model
        self.fallback_model = fallback_model
        self._router = openrouter_client or OpenRouterClient(
            api_key=api_key,
            primary_model=primary_model,
            fallback_model=fallback_model,
            timeout=timeout,
            client=client,
        )
        self.last_metadata: dict = {}

    def generate(self, context: PlanContext) -> AIPlanContent:
        self.last_metadata = {
            "configured_provider": self.name,
            "configured_primary_model": self.primary_model,
            "actual_model": None,
            "fallback_used": False,
            "latency_ms": None,
            "success": False,
            "validation_success": False,
        }
        try:
            completion = self._router.complete(
                [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": context.model_dump_json()},
                ],
                temperature=0,
            )
            self.last_metadata.update(
                actual_model=completion.actual_model,
                fallback_used=completion.actual_model is not None and completion.actual_model != self.primary_model,
                latency_ms=completion.latency_ms,
                success=True,
            )
            try:
                return AIPlanContent.model_validate(replan_protocol.parse_json_object(completion.content))
            except (ValueError, ValidationError, TypeError):
                self.last_metadata["success"] = False
                raise ProviderError("invalid_response") from None
        except ProviderError:
            actual_model = self._router.last_actual_model
            self.last_metadata.update(
                actual_model=actual_model,
                fallback_used=actual_model is not None and actual_model != self.primary_model,
                latency_ms=self._router.last_latency_ms,
            )
            raise

    def generate_replan(self, payload: dict) -> ReplanDraft:
        """One bounded call in the compact edit protocol. Transport failures keep their
        reason (timeout, rate limit, unavailable) so the user gets the right message."""
        completion = self._router.complete(
            [
                {"role": "system", "content": replan_protocol.SYSTEM_PROMPT},
                {"role": "user", "content": replan_protocol.user_message(payload, payload.get("_feedback"))},
            ],
            temperature=0,
            schema=replan_protocol.EDIT_SCHEMA,
            timeout=payload.get("_timeout_seconds"),
            max_tokens=700,
        )
        try:
            return replan_protocol.to_draft(completion.content, payload)
        except replan_protocol.EditProtocolError as exc:
            raise ProviderError(f"invalid_response:{exc.code}") from None
