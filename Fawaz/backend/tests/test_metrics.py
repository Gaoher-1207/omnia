"""Operational events for AI latency/fallbacks, the replan lifecycle and plan outcomes."""

import logging
from datetime import UTC, datetime, timedelta

import pytest

from app.core import metrics
from tests.test_replanning import ReplanningProvider, configure, make_proposal, setup_day


@pytest.fixture(autouse=True)
def clean_metrics():
    metrics.reset()
    yield
    metrics.reset()


@pytest.fixture
def fixed_clock(clock):
    now = datetime(2026, 10, 4, 9, 0, tzinfo=UTC)
    clock.set(now)
    return now


def test_metric_lines_are_structured_and_hold_no_user_content(caplog):
    with caplog.at_level(logging.INFO, logger="omnia.metrics"):
        metrics.record("ai.plan", provider="ollama", result="fallback", latency_ms=12)
    assert caplog.records[-1].getMessage() == "metric event=ai.plan provider=ollama result=fallback latency_ms=12"
    # Latency is reported, but never splits the counts.
    metrics.record("ai.plan", provider="ollama", result="fallback", latency_ms=99)
    assert metrics.count("ai.plan", provider="ollama", result="fallback") == 2


def test_plan_generation_records_provider_result_and_latency(app, client, headers, fixed_clock, caplog):
    configure(app, ReplanningProvider(failure=True))  # its generate() works; only replans fail
    with caplog.at_level(logging.INFO, logger="omnia.metrics"):
        setup_day(client, headers, fixed_clock)
    assert metrics.count("ai.plan", provider="test", result="primary") == 1
    assert any("latency_ms=" in record.getMessage() for record in caplog.records)
    assert not any("Finish assignment" in record.getMessage() for record in caplog.records)


def test_replan_lifecycle_is_counted(app, client, headers, fixed_clock, clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)

    applied = make_proposal(client, headers).json()
    assert metrics.count("ai.replan.proposal", result="created", fallback_used=False) == 1
    client.post(f"/api/ai/replan/proposals/{applied['id']}/apply", headers=headers)
    assert metrics.count("ai.replan.apply", result="applied") == 1
    client.post(f"/api/ai/replan/proposals/{applied['id']}/apply", headers=headers)
    assert metrics.count("ai.replan.apply", result="not_pending") == 1

    dismissed = make_proposal(client, headers).json()
    client.post(f"/api/ai/replan/proposals/{dismissed['id']}/dismiss", headers=headers)
    assert metrics.count("ai.replan.dismiss", result="dismissed") == 1

    expired = make_proposal(client, headers).json()
    clock.set(fixed_clock + timedelta(minutes=31))
    client.post(f"/api/ai/replan/proposals/{expired['id']}/apply", headers=headers)
    assert metrics.count("ai.replan.apply", result="expired") == 1

    clock.set(fixed_clock)
    stale = make_proposal(client, headers).json()
    current = client.get("/api/ai/daily-plan", headers=headers).json()
    block = current["items"][0]
    client.put(
        f"/api/ai/daily-plan/{plan['plan_date']}/items/{block['item_key']}/outcome",
        headers=headers,
        json={"status": "done"},
    )
    assert metrics.count("plan.outcome", status="done") == 1
    client.post(f"/api/ai/replan/proposals/{stale['id']}/apply", headers=headers)
    assert metrics.count("ai.replan.apply", result="stale") == 1


def test_replan_fallback_is_counted(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider(failure=True))
    setup_day(client, headers, fixed_clock)
    assert make_proposal(client, headers).status_code == 201
    assert metrics.count("ai.replan.proposal", provider="test", result="created", fallback_used=True) == 1
