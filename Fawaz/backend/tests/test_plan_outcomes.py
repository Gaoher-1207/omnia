"""Plan-block outcomes: what actually happened, recorded explicitly by the owner."""

from datetime import UTC, datetime, timedelta

import pytest

from app.modules.ai.providers import RulesProvider
from app.modules.ai.schemas import ContextOutcome, ContextStudyBlock, ContextTask
from tests.test_ai import context
from tests.test_replanning import ReplanningProvider, configure, make_proposal, setup_day


@pytest.fixture
def fixed_clock(clock):
    now = datetime(2026, 10, 4, 9, 0, tzinfo=UTC)
    clock.set(now)
    return now


def _url(plan, item, day=None):
    return f"/api/ai/daily-plan/{day or plan['plan_date']}/items/{item['item_key']}/outcome"


def _task_block(plan):
    return next(item for item in plan["items"] if item["category"] == "task")


def test_outcome_round_trip_is_attached_to_the_block(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    assert all(item["outcome"] is None for item in plan["items"])
    block = _task_block(plan)

    recorded = client.put(_url(plan, block), headers=headers, json={"status": "done"})
    assert recorded.status_code == 200, recorded.text
    assert _task_block(recorded.json())["outcome"] == "done"
    # The schedule itself is untouched: same plan, same revision, same times.
    assert recorded.json()["id"] == plan["id"] and recorded.json()["revision"] == plan["revision"]
    assert _task_block(recorded.json())["start"] == block["start"]

    again = client.get("/api/ai/daily-plan", headers=headers).json()
    assert _task_block(again)["outcome"] == "done"
    dashboard = client.get("/api/dashboard", headers=headers).json()
    assert _task_block(dashboard["ai_plan"])["outcome"] == "done"

    changed = client.put(_url(plan, block), headers=headers, json={"status": "skipped"}).json()
    assert _task_block(changed)["outcome"] == "skipped"
    cleared = client.delete(_url(plan, block), headers=headers)
    assert cleared.status_code == 200
    assert _task_block(cleared.json())["outcome"] is None
    # Clearing twice is harmless.
    assert client.delete(_url(plan, block), headers=headers).status_code == 200


def test_marking_a_task_block_done_completes_the_task(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    block = _task_block(plan)
    task_id = block["task_id"]

    response = client.put(_url(plan, block), headers=headers, json={"status": "done"})

    assert response.status_code == 200, response.text
    tasks = client.get("/api/tasks?status=done", headers=headers)
    assert tasks.status_code == 200, tasks.text
    completed = next((task for task in tasks.json()["items"] if task["id"] == task_id), None)
    assert completed is not None
    assert completed["status"] == "done"
    assert completed["completed_at"] is not None


def test_outcomes_are_validated_and_owner_scoped(app, client, headers, other_headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    block = _task_block(plan)
    assert client.put(_url(plan, block), headers=headers, json={"status": "maybe"}).status_code == 422
    assert client.put(_url(plan, block), headers=headers, json={"status": "done", "user_id": "x"}).status_code == 422
    # Another account has no plan for the day, and can never touch this one.
    assert client.put(_url(plan, block), headers=other_headers, json={"status": "done"}).status_code == 404
    assert client.get("/api/ai/daily-plan", headers=headers).json()["items"][0]["outcome"] is None
    assert client.put(_url(plan, block), json={"status": "done"}).status_code == 401
    # Unknown block: the client is looking at an outdated plan.
    stale = client.put(_url(plan, {"item_key": "not-a-block"}), headers=headers, json={"status": "done"})
    assert stale.status_code == 409 and stale.json()["error"]["code"] == "plan_item_stale"
    # Tomorrow hasn't happened yet.
    tomorrow = (fixed_clock.date() + timedelta(days=1)).isoformat()
    future = client.put(_url(plan, block, tomorrow), headers=headers, json={"status": "done"})
    assert future.status_code == 422 and future.json()["error"]["code"] == "plan_outcome_invalid"


def test_outcome_survives_a_replan_that_moves_the_block(app, client, headers, fixed_clock):
    def move_task(items):
        return [{**item, "start": "15:00", "end": "15:30"} if item["category"] == "task" else item for item in items]

    configure(app, ReplanningProvider(transform=move_task))
    plan = setup_day(client, headers, fixed_clock)
    block = _task_block(plan)
    client.put(_url(plan, block), headers=headers, json={"status": "partial"})
    proposal = make_proposal(client, headers, "Move Finish assignment to 15:00").json()
    applied = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert applied.status_code == 200, applied.text
    moved = _task_block(applied.json())
    assert moved["start"] == "15:00"
    assert moved["item_key"] == block["item_key"]
    assert moved["outcome"] == "partial"


def test_recording_an_outcome_makes_an_open_proposal_stale(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    plan = setup_day(client, headers, fixed_clock)
    proposal = make_proposal(client, headers).json()
    client.put(_url(plan, _task_block(plan)), headers=headers, json={"status": "done"})
    response = client.post(f"/api/ai/replan/proposals/{proposal['id']}/apply", headers=headers)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "replan_proposal_stale"
    # The plan kept its revision; nothing was applied over the new outcome.
    current = client.get("/api/ai/daily-plan", headers=headers).json()
    assert current["revision"] == plan["revision"]
    assert _task_block(current)["outcome"] == "done"


def test_replanning_reads_outcomes_and_does_not_plan_done_work_again(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider(failure=True))  # use the deterministic rules replanner
    plan = setup_day(client, headers, fixed_clock)
    block = _task_block(plan)
    client.put(_url(plan, block), headers=headers, json={"status": "done"})
    proposal = make_proposal(client, headers)
    assert proposal.status_code == 201, proposal.text
    body = proposal.json()
    # The due-today task is done, so it is neither required nor rescheduled.
    assert not any(item["category"] == "task" for item in body["schedule"])
    assert not any("No outcomes are recorded" in warning for warning in body["warnings"])
    removed = next(op for op in body["operations"] if op["item_key"] == block["item_key"])
    assert removed["kind"] == "REMOVE"


def test_without_outcomes_the_proposal_says_past_blocks_are_history(app, client, headers, fixed_clock):
    configure(app, ReplanningProvider())
    setup_day(client, headers, fixed_clock)
    warnings = make_proposal(client, headers).json()["warnings"]
    assert any("No outcomes are recorded" in warning for warning in warnings)


def _work_context(outcomes=()):
    return context(
        open_tasks=[
            ContextTask(ref="t1", title="Essay", priority="high", due_in_days=0, estimated_minutes=30),
        ],
        study_blocks=[ContextStudyBlock(ref="b1", subject="DBMS", title="Revision", minutes=60, reason="Exam soon")],
        plan_outcomes=list(outcomes),
    )


def _outcome(key, category, status, **refs):
    return ContextOutcome(item_key=key, title=key, category=category, start="10:00", end="11:00", status=status, **refs)


def test_rules_planner_skips_done_tasks_study_and_workout():
    before = RulesProvider().generate(_work_context())
    assert any(item.task_ref == "t1" for item in before.items)
    assert any(item.study_ref == "b1" for item in before.items)
    assert any(item.category == "fitness" and "Workout" in item.title for item in before.items)

    after = RulesProvider().generate(
        _work_context(
            [
                _outcome("a", "task", "done", task_ref="t1"),
                _outcome("b", "study", "done", study_ref="b1"),
                _outcome("c", "fitness", "done"),
            ]
        )
    )
    assert not any(item.task_ref == "t1" for item in after.items)
    assert not any(item.study_ref == "b1" for item in after.items)
    assert not any(item.category == "fitness" and "Workout" in item.title for item in after.items)
    assert any("already done" in note for note in after.adjustments)


def test_partial_and_skipped_work_is_still_planned():
    for status in ("partial", "skipped"):
        plan = RulesProvider().generate(
            _work_context(
                [_outcome("a", "task", status, task_ref="t1"), _outcome("b", "study", status, study_ref="b1")]
            )
        )
        assert any(item.task_ref == "t1" for item in plan.items), status
        assert sum(1 for item in plan.items if item.study_ref == "b1") >= 1, status
