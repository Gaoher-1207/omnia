import base64
import json
from datetime import date, timedelta

import httpx

from app.modules.ai.providers import RulesProvider
from app.modules.ai.schemas import ContextSleep, ContextStudyBlock
from app.modules.nutrition.estimator import AnthropicFoodEstimator, get_estimator
from tests.conftest import auth_headers, register
from tests.test_ai import context

PNG = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 64).decode()
TODAY = date.today()


# ---- tasks: fields the Flutter app needs


def test_task_time_estimate_and_category_round_trip(client, headers):
    body = {
        "title": "Revise joins",
        "due_date": TODAY.isoformat(),
        "due_time": "18:30",
        "estimated_minutes": 40,
        "category": "study",
    }
    task = client.post("/api/tasks", json=body, headers=headers).json()
    assert task["due_time"] == "18:30:00"
    assert task["estimated_minutes"] == 40 and task["category"] == "study"
    cleared = client.patch(f"/api/tasks/{task['id']}", json={"due_date": None}, headers=headers).json()
    assert cleared["due_date"] is None and cleared["due_time"] is None
    assert client.post("/api/tasks", json={"title": "x", "due_time": "10:00"}, headers=headers).status_code == 422
    assert client.post("/api/tasks", json={"title": "x", "category": "gaming"}, headers=headers).status_code == 422
    assert client.post("/api/tasks", json={"title": "x", "estimated_minutes": 0}, headers=headers).status_code == 422
    assert client.patch(f"/api/tasks/{task['id']}", json={"category": None}, headers=headers).status_code == 422


# ---- profile


def test_profile_goals_and_unique_username(client, headers, other_headers):
    updated = client.patch(
        "/api/profile",
        json={"daily_sleep_goal_minutes": 450, "daily_calorie_goal": 2200, "username": "  Riya_07 "},
        headers=headers,
    ).json()
    assert updated["username"] == "riya_07"
    assert updated["daily_sleep_goal_minutes"] == 450 and updated["daily_calorie_goal"] == 2200
    taken = client.patch("/api/profile", json={"username": "RIYA_07"}, headers=other_headers)
    assert taken.status_code == 409
    assert client.patch("/api/profile", json={"username": "a b"}, headers=other_headers).status_code == 422
    assert client.patch("/api/profile", json={"username": "ok_name"}, headers=other_headers).status_code == 200


# ---- sleep


def test_sleep_upsert_range_and_privacy(client, headers, other_headers):
    yesterday = TODAY - timedelta(days=1)
    first = client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 400, "quality": 4}, headers=headers)
    again = client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 420, "quality": 3}, headers=headers)
    assert first.status_code == again.status_code == 200
    assert first.json()["id"] == again.json()["id"] and again.json()["duration_minutes"] == 420
    client.put(f"/api/sleep/{yesterday}", json={"duration_minutes": 360}, headers=headers)

    data = client.get(f"/api/sleep?from={TODAY - timedelta(days=6)}&to={TODAY}", headers=headers).json()
    assert len(data["days"]) == 7 and data["average_minutes"] == 390 and data["goal_minutes"] == 480
    assert data["days"][0]["logged"] is False

    assert client.get(f"/api/sleep/{TODAY}", headers=other_headers).json()["logged"] is False
    assert client.delete(f"/api/sleep/{TODAY}", headers=other_headers).status_code == 404
    assert client.delete(f"/api/sleep/{TODAY}", headers=headers).status_code == 204


def test_sleep_validation(client, headers):
    assert client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 1500}, headers=headers).status_code == 422
    assert (
        client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 400, "quality": 6}, headers=headers).status_code
        == 422
    )
    future = client.put(f"/api/sleep/{TODAY + timedelta(days=2)}", json={"duration_minutes": 400}, headers=headers)
    assert future.status_code == 422


# ---- meals


def test_meals_crud_totals_and_privacy(client, headers, other_headers):
    empty = client.get("/api/meals", headers=headers).json()
    assert empty["meals"] == [] and empty["totals"]["calories"] == 0 and empty["calorie_goal"] == 2000

    a = client.post(
        "/api/meals",
        json={"meal_type": "lunch", "description": "Dal rice", "calories": 520, "protein_g": 18},
        headers=headers,
    )
    assert a.status_code == 201
    client.post("/api/meals", json={"meal_type": "snack", "description": "Apple", "calories": 95}, headers=headers)
    day = client.get("/api/meals", headers=headers).json()
    assert day["totals"]["calories"] == 615 and len(day["meals"]) == 2

    meal_id = a.json()["id"]
    assert client.patch(f"/api/meals/{meal_id}", json={"calories": 480}, headers=headers).json()["calories"] == 480
    assert client.patch(f"/api/meals/{meal_id}", json={"calories": 1}, headers=other_headers).status_code == 404
    assert client.delete(f"/api/meals/{meal_id}", headers=other_headers).status_code == 404
    assert client.get("/api/meals", headers=other_headers).json()["meals"] == []

    summary = client.get("/api/nutrition/summary", headers=headers).json()
    assert len(summary["days"]) == 7 and summary["days"][-1]["calories"] == 575

    assert client.delete(f"/api/meals/{meal_id}", headers=headers).status_code == 204


def test_meal_validation(client, headers):
    bad = [
        {"meal_type": "brunch", "description": "x"},
        {"meal_type": "lunch", "description": " "},
        {"meal_type": "lunch", "description": "x", "calories": -1},
        {"meal_type": "lunch", "description": "x", "day": (TODAY + timedelta(days=3)).isoformat()},
    ]
    for body in bad:
        assert client.post("/api/meals", json=body, headers=headers).status_code == 422, body


# ---- food photo estimate


def test_photo_estimate_not_configured_is_503(client, headers):
    response = client.post(
        "/api/nutrition/estimate", json={"image_base64": PNG, "media_type": "image/png"}, headers=headers
    )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "service_unavailable"


def test_photo_estimate_rejects_bad_images(client, headers):
    not_b64 = client.post(
        "/api/nutrition/estimate", json={"image_base64": "%%%", "media_type": "image/png"}, headers=headers
    )
    assert not_b64.status_code == 422
    wrong_type = client.post(
        "/api/nutrition/estimate", json={"image_base64": PNG, "media_type": "image/jpeg"}, headers=headers
    )
    assert wrong_type.status_code == 422
    gif = client.post("/api/nutrition/estimate", json={"image_base64": PNG, "media_type": "image/gif"}, headers=headers)
    assert gif.status_code == 422
    assert (
        client.post("/api/nutrition/estimate", json={"image_base64": PNG, "media_type": "image/png"}).status_code == 401
    )


def _estimator(handler):
    return AnthropicFoodEstimator(
        api_key="k",
        model="m",
        base_url="https://ai.invalid",
        timeout=5,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )


def test_photo_estimate_success_sends_only_the_photo(app, client, headers, user):
    sent = {}

    def handler(request):
        sent["body"] = request.content.decode()
        reply = {
            "items": [
                {"name": "Rice", "portion": "1 cup", "calories": 200, "protein_g": 4, "carbs_g": 45, "fat_g": 0},
                {"name": "Dal", "portion": "1 bowl", "calories": 180, "protein_g": 12, "carbs_g": 25, "fat_g": 3},
            ],
            "confidence": "medium",
            "suggested_description": "Dal and rice",
        }
        return httpx.Response(200, json={"content": [{"type": "text", "text": json.dumps(reply)}]})

    app.dependency_overrides[get_estimator] = lambda: _estimator(handler)
    response = client.post(
        "/api/nutrition/estimate",
        json={"image_base64": PNG, "media_type": "image/png", "note": "home cooked"},
        headers=headers,
    )
    assert response.status_code == 200
    estimate = response.json()
    assert estimate["totals"] == {"calories": 380, "protein_g": 16, "carbs_g": 70, "fat_g": 3}
    assert estimate["confidence"] == "medium"
    assert user["user"]["email"] not in sent["body"] and user["user"]["id"] not in sent["body"]
    assert client.get("/api/meals", headers=headers).json()["meals"] == [], "estimates are never saved"


def test_photo_estimate_provider_failures_are_502(app, client, headers):
    for handler in (
        lambda r: httpx.Response(500, json={}),
        lambda r: httpx.Response(200, json={"content": [{"type": "text", "text": "a nice curry"}]}),
        lambda r: (_ for _ in ()).throw(httpx.ReadTimeout("slow")),
    ):
        app.dependency_overrides[get_estimator] = lambda h=handler: _estimator(h)
        response = client.post(
            "/api/nutrition/estimate", json={"image_base64": PNG, "media_type": "image/png"}, headers=headers
        )
        assert response.status_code == 502
        assert "by hand" in response.json()["error"]["message"]


# ---- dashboard + progress + adaptive planning


def test_dashboard_and_progress_include_sleep_and_calories(client, headers):
    client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 410}, headers=headers)
    client.post("/api/meals", json={"meal_type": "breakfast", "description": "Oats", "calories": 300}, headers=headers)
    client.put(
        f"/api/activity/{TODAY}", json={"steps": 100, "workout_done": True, "workout_minutes": 25}, headers=headers
    )
    today = client.get("/api/dashboard", headers=headers).json()["today"]
    assert today["sleep_minutes"] == 410 and today["calories"] == 300 and today["workout_minutes"] == 25
    last = client.get("/api/progress", headers=headers).json()["history"][-1]
    assert last["sleep_minutes"] == 410 and last["calories"] == 300


def test_rules_planner_lightens_day_after_short_sleep():
    blocks = [ContextStudyBlock(subject="Maths", title="Series", minutes=70, reason="r")]
    plan = RulesProvider().generate(context(last_night_sleep=ContextSleep(minutes=290), study_blocks=blocks))
    assert any("You slept 4h 50m" in a for a in plan.adjustments)
    assert any("Light" in i.title for i in plan.items if i.category == "fitness")
    rested = RulesProvider().generate(
        context(last_night_sleep=ContextSleep(minutes=480, quality=4), study_blocks=blocks)
    )
    assert not any("slept" in a for a in rested.adjustments)


def test_ai_context_includes_sleep_but_no_identity(app, client, headers, user):
    from app.modules.ai.service import get_provider
    from tests.test_ai import _anthropic, _reply

    client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 300, "quality": 2}, headers=headers)
    seen = {}

    def handler(request):
        seen["payload"] = json.loads(request.content)["messages"][0]["content"]
        return _reply({"summary": "Light day.", "items": [], "tips": [], "adjustments": []})

    app.dependency_overrides[get_provider] = lambda: _anthropic(handler)
    assert client.post("/api/ai/daily-plan", json={}, headers=headers).status_code == 201
    payload = json.loads(seen["payload"])
    assert payload["last_night_sleep"] == {"minutes": 300, "quality": 2}
    assert user["user"]["email"] not in seen["payload"]


def test_new_modules_require_auth(client):
    for method, path in (
        ("get", "/api/sleep"),
        ("put", f"/api/sleep/{TODAY}"),
        ("get", "/api/meals"),
        ("post", "/api/meals"),
        ("get", "/api/nutrition/summary"),
    ):
        assert getattr(client, method)(path).status_code == 401, path


def test_other_user_isolated_from_new_data(client):
    a = auth_headers(register(client))
    b = auth_headers(register(client))
    client.put(f"/api/sleep/{TODAY}", json={"duration_minutes": 333}, headers=a)
    client.post("/api/meals", json={"meal_type": "dinner", "description": "Pasta", "calories": 700}, headers=a)
    assert client.get("/api/dashboard", headers=b).json()["today"]["calories"] == 0
    assert client.get("/api/sleep", headers=b).json()["average_minutes"] is None
