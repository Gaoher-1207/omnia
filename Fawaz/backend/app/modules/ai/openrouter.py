"""OpenRouter daily-plan provider: strict parse; service owns final validation."""

import httpx
from pydantic import ValidationError

from app.modules.ai.openrouter_client import OpenRouterClient
from app.modules.ai.providers import SYSTEM_PROMPT, ProviderError, _extract_json
from app.modules.ai.schemas import AIPlanContent, PlanContext


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
                return AIPlanContent.model_validate(_extract_json(completion.content))
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
