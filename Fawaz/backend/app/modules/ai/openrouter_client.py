"""Shared OpenRouter chat-completions transport for OmniAI capabilities."""

import time
from dataclasses import dataclass

import httpx

from app.modules.ai.providers import ProviderError


@dataclass(frozen=True)
class OpenRouterCompletion:
    content: str
    actual_model: str | None
    latency_ms: int


class OpenRouterClient:
    url = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(
        self,
        *,
        api_key: str,
        primary_model: str,
        fallback_model: str,
        timeout: float,
        client: httpx.Client | None = None,
    ):
        self._api_key = api_key
        self.primary_model = primary_model
        self.fallback_model = fallback_model
        self._timeout = timeout
        self._client = client
        self.last_completion: OpenRouterCompletion | None = None
        self.last_actual_model: str | None = None
        self.last_latency_ms: int | None = None

    def complete(self, messages: list[dict[str, str]], *, temperature: float = 0) -> OpenRouterCompletion:
        payload = {
            "model": self.primary_model,
            "models": [self.fallback_model],
            "temperature": temperature,
            "messages": messages,
        }
        client = self._client or httpx.Client(timeout=self._timeout)
        started = time.perf_counter()
        self.last_completion = None
        self.last_actual_model = None
        self.last_latency_ms = None
        try:
            try:
                response = client.post(
                    self.url,
                    json=payload,
                    headers={"Authorization": f"Bearer {self._api_key}", "Content-Type": "application/json"},
                    timeout=self._timeout,
                )
            except httpx.TimeoutException:
                raise ProviderError("provider_timeout") from None
            except httpx.HTTPError:
                raise ProviderError("provider_unreachable") from None

            if response.status_code == 429:
                raise ProviderError("provider_rate_limited")
            if response.status_code >= 500:
                raise ProviderError("provider_unavailable")
            if response.status_code >= 400:
                raise ProviderError("provider_error")

            try:
                body = response.json()
                model = body.get("model")
                self.last_actual_model = model if isinstance(model, str) else None
                content = body["choices"][0]["message"]["content"]
                if not isinstance(content, str) or not content.strip():
                    raise ValueError("empty or non-text completion")
            except (ValueError, AttributeError, KeyError, IndexError, TypeError):
                raise ProviderError("invalid_response") from None

            completion = OpenRouterCompletion(
                content=content,
                actual_model=model if isinstance(model, str) else None,
                latency_ms=round((time.perf_counter() - started) * 1000),
            )
            self.last_completion = completion
            return completion
        finally:
            self.last_latency_ms = round((time.perf_counter() - started) * 1000)
            if self._client is None:
                client.close()
