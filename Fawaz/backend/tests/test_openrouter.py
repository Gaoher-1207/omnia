import json
from datetime import UTC, datetime

import httpx
import pytest

from app.core.config import get_settings
from app.modules.ai.models import AIPlan
from app.modules.ai.ollama import OllamaPlanProvider
from app.modules.ai.openrouter import OpenRouterPlanProvider
from app.modules.ai.providers import ProviderError
from app.modules.ai.service import get_provider


@pytest.fixture(autouse=True)
def clock(monkeypatch):
    monkeypatch.setattr("app.core.time.utcnow", lambda: datetime(2026, 9, 28, 9, tzinfo=UTC))


def candidate(**changes):
    return {
        "summary": "Work first",
        "items": [{"start": "10:00", "end": "10:30", "category": "task", "title": "Proposal", "task_ref": "t1"}],
        "tips": [],
        "adjustments": [],
        **changes,
    }


def test_openrouter_request_uses_primary_then_free_router_without_response_format():
    sent = {}

    def handler(request):
        sent["headers"] = request.headers
        sent["body"] = json.loads(request.content)
        return httpx.Response(
            200,
            json={"model": "openrouter/served-model", "choices": [{"message": {"content": json.dumps(candidate())}}]},
        )

    provider = OpenRouterPlanProvider(
        api_key="server-secret",
        primary_model="nvidia/nemotron-3-ultra-550b-a55b:free",
        fallback_model="openrouter/free",
        timeout=2,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    from app.modules.ai.schemas import PlanContext

    provider.generate(PlanContext.model_construct())
    assert sent["body"]["model"] == "nvidia/nemotron-3-ultra-550b-a55b:free"
    assert sent["body"]["models"] == ["openrouter/free"]
    assert "response_format" not in sent["body"]
    assert sent["headers"]["authorization"] == "Bearer server-secret"
    assert provider.last_metadata["actual_model"] == "openrouter/served-model"
    assert provider.last_metadata["fallback_used"] is True


def test_openrouter_rejects_malformed_structured_output():
    provider = OpenRouterPlanProvider(
        api_key="key",
        primary_model="nvidia/nemotron-3-ultra-550b-a55b:free",
        fallback_model="openrouter/free",
        timeout=2,
        client=httpx.Client(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(
                    200,
                    json={
                        "model": "nvidia/nemotron-3-ultra-550b-a55b:free",
                        "choices": [{"message": {"content": "not json"}}],
                    },
                )
            )
        ),
    )
    from app.modules.ai.schemas import PlanContext

    with pytest.raises(ProviderError, match="invalid_response"):
        provider.generate(PlanContext.model_construct())
    assert provider.last_metadata["actual_model"] == "nvidia/nemotron-3-ultra-550b-a55b:free"
    assert provider.last_metadata["success"] is False


@pytest.mark.parametrize(
    "error, reason",
    [
        (httpx.ReadTimeout("timeout"), "provider_timeout"),
        (httpx.ConnectError("offline"), "provider_unreachable"),
    ],
)
def test_openrouter_transport_errors_are_safe_provider_errors(error, reason):
    def handler(request):
        raise error

    provider = OpenRouterPlanProvider(
        api_key="key",
        primary_model="nvidia/nemotron-3-ultra-550b-a55b:free",
        fallback_model="openrouter/free",
        timeout=1,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    from app.modules.ai.schemas import PlanContext

    with pytest.raises(ProviderError) as exc:
        provider.generate(PlanContext.model_construct())
    assert exc.value.reason == reason


def test_provider_selection_keeps_ollama_and_supports_openrouter(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "omnia_ai_provider", None)
    monkeypatch.setattr(settings, "planner_ai_provider", "ollama")
    assert isinstance(get_provider(), OllamaPlanProvider)

    monkeypatch.setattr(settings, "planner_ai_provider", "openrouter")
    monkeypatch.setattr(settings, "openrouter_api_key", "server-secret")
    provider = get_provider()
    assert isinstance(provider, OpenRouterPlanProvider)
    assert provider.name == "openrouter"
    assert provider.primary_model == "nvidia/nemotron-3-ultra-550b-a55b:free"
    assert provider.fallback_model == "openrouter/free"
    monkeypatch.setattr(settings, "omnia_ai_provider", "ollama")
    assert isinstance(get_provider(), OpenRouterPlanProvider)


def test_openrouter_configuration_requires_backend_key():
    from pydantic import ValidationError

    from app.core.config import Settings

    with pytest.raises(ValidationError, match="OPENROUTER_API_KEY"):
        Settings(planner_ai_provider="openrouter", openrouter_api_key="")


def test_food_photo_configuration_remains_independent(monkeypatch):
    from app.modules.nutrition.estimator import AnthropicFoodEstimator, get_estimator

    settings = get_settings()
    monkeypatch.setattr(settings, "omnia_ai_provider", None)
    monkeypatch.setattr(settings, "ai_provider", "anthropic")
    monkeypatch.setattr(settings, "ai_api_key", "food-photo-key")
    monkeypatch.setattr(settings, "planner_ai_provider", "rules")
    assert isinstance(get_estimator(), AnthropicFoodEstimator)
    assert get_provider().name == "rules"

    monkeypatch.setattr(settings, "planner_ai_provider", "openrouter")
    monkeypatch.setattr(settings, "openrouter_api_key", "openrouter-key")
    assert isinstance(get_estimator(), AnthropicFoodEstimator)
    assert isinstance(get_provider(), OpenRouterPlanProvider)


@pytest.mark.parametrize(
    "served_model, expected_fallback",
    [
        ("nvidia/nemotron-3-ultra-550b-a55b:free", False),
        ("some-free-model/served", True),
    ],
)
def test_openrouter_endpoint_fallback_is_validated_and_key_is_not_returned(
    app, client, headers, db, monkeypatch, caplog, served_model, expected_fallback
):
    from app.modules.ai.models import AIPlan

    settings = get_settings()
    monkeypatch.setattr(settings, "omnia_ai_provider", None)
    monkeypatch.setattr(settings, "planner_ai_provider", "openrouter")
    monkeypatch.setattr(settings, "openrouter_api_key", "server-only-secret")

    def handler(request):
        assert request.headers["authorization"] == "Bearer server-only-secret"
        return httpx.Response(
            200,
            json={
                "model": served_model,
                "choices": [{"message": {"content": json.dumps(candidate(items=[]))}}],
            },
        )

    from app.modules.ai.service import get_provider as service_provider

    app.dependency_overrides[service_provider] = lambda: OpenRouterPlanProvider(
        api_key="server-only-secret",
        primary_model="nvidia/nemotron-3-ultra-550b-a55b:free",
        fallback_model="openrouter/free",
        timeout=2,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    response = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert response.status_code == 201
    assert response.json()["source"] == "openrouter"
    assert response.json()["is_fallback"] is False
    assert "server-only-secret" not in response.text
    assert db.query(AIPlan).one().source == "openrouter"
    assert f"actual_model={served_model}" in caplog.text
    assert f"fallback_used={str(expected_fallback)}" in caplog.text
    assert "validation_success=True" in caplog.text


def test_openrouter_rejected_proposal_uses_deterministic_fallback(app, client, headers, db, monkeypatch):
    from app.modules.ai.service import get_provider as service_provider

    provider = OpenRouterPlanProvider(
        api_key="key",
        primary_model="nvidia/nemotron-3-ultra-550b-a55b:free",
        fallback_model="openrouter/free",
        timeout=2,
        client=httpx.Client(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(
                    200,
                    json={
                        "model": "free-model",
                        "choices": [
                            {
                                "message": {
                                    "content": json.dumps(
                                        candidate(
                                            items=[
                                                {
                                                    "start": "09:00",
                                                    "end": "09:30",
                                                    "category": "task",
                                                    "title": "bad",
                                                    "task_ref": "t999",
                                                }
                                            ]
                                        )
                                    )
                                }
                            }
                        ],
                    },
                )
            )
        ),
    )
    app.dependency_overrides[service_provider] = lambda: provider
    response = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert response.status_code == 201
    assert response.json()["source"] == "rules"
    assert response.json()["is_fallback"] is True
    assert db.query(AIPlan).one().source == "rules"


def test_openrouter_both_models_unavailable_degrades_to_rules(app, client, headers, db, monkeypatch):
    from app.modules.ai.models import AIPlan
    from app.modules.ai.service import get_provider as service_provider

    provider = OpenRouterPlanProvider(
        api_key="key",
        primary_model="nvidia/nemotron-3-ultra-550b-a55b:free",
        fallback_model="openrouter/free",
        timeout=2,
        client=httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(429))),
    )
    app.dependency_overrides[service_provider] = lambda: provider
    response = client.post("/api/ai/daily-plan", headers=headers, json={})
    assert response.status_code == 201
    assert response.json()["source"] == "rules"
    assert response.json()["is_fallback"] is True
    assert db.query(AIPlan).one().source == "rules"
