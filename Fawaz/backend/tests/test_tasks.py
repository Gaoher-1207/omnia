from datetime import date, timedelta


def test_task_crud_flow(client, headers):
    created = client.post(
        "/api/tasks",
        json={
            "title": "  Finish lab report  ",
            "priority": "high",
            "due_date": date.today().isoformat(),
        },
        headers=headers,
    )
    assert created.status_code == 201
    task = created.json()
    assert task["title"] == "Finish lab report"
    assert task["status"] == "todo"
    assert task["completed_at"] is None

    done = client.patch(f"/api/tasks/{task['id']}", json={"status": "done"}, headers=headers)
    assert done.status_code == 200
    assert done.json()["completed_at"] is not None

    reopened = client.patch(f"/api/tasks/{task['id']}", json={"status": "todo"}, headers=headers)
    assert reopened.json()["completed_at"] is None

    assert client.delete(f"/api/tasks/{task['id']}", headers=headers).status_code == 204
    assert client.get(f"/api/tasks/{task['id']}", headers=headers).status_code == 404


def test_task_validation(client, headers):
    assert client.post("/api/tasks", json={"title": "   "}, headers=headers).status_code == 422
    assert client.post("/api/tasks", json={"title": "x" * 201}, headers=headers).status_code == 422
    assert client.post("/api/tasks", json={"title": "ok", "priority": "urgent"}, headers=headers).status_code == 422
    task = client.post("/api/tasks", json={"title": "ok"}, headers=headers).json()
    assert client.patch(f"/api/tasks/{task['id']}", json={"title": None}, headers=headers).status_code == 422
    assert client.patch(f"/api/tasks/{task['id']}", json={"status": "archived"}, headers=headers).status_code == 422
    assert client.get("/api/tasks/not-a-uuid", headers=headers).status_code == 422


def test_cannot_smuggle_user_id(client, headers):
    response = client.post(
        "/api/tasks", json={"title": "x", "user_id": "00000000-0000-0000-0000-000000000000"}, headers=headers
    )
    assert response.status_code == 422


def test_other_users_cannot_see_or_change_my_tasks(client, headers, other_headers):
    task = client.post("/api/tasks", json={"title": "Mine"}, headers=headers).json()
    url = f"/api/tasks/{task['id']}"
    assert client.get(url, headers=other_headers).status_code == 404
    assert client.patch(url, json={"title": "Hacked"}, headers=other_headers).status_code == 404
    assert client.delete(url, headers=other_headers).status_code == 404
    assert client.get("/api/tasks", headers=other_headers).json()["total"] == 0
    assert client.get(url, headers=headers).json()["title"] == "Mine"


def test_list_filters_ordering_and_pagination(client, headers):
    today = date.today()
    client.post(
        "/api/tasks", json={"title": "later", "due_date": (today + timedelta(days=5)).isoformat()}, headers=headers
    )
    client.post("/api/tasks", json={"title": "no date", "priority": "high"}, headers=headers)
    soon = client.post("/api/tasks", json={"title": "soon", "due_date": today.isoformat()}, headers=headers).json()
    done = client.post("/api/tasks", json={"title": "done one"}, headers=headers).json()
    client.patch(f"/api/tasks/{done['id']}", json={"status": "done"}, headers=headers)

    everything = client.get("/api/tasks", headers=headers).json()
    assert everything["total"] == 4
    assert [t["title"] for t in everything["items"]] == ["soon", "later", "no date", "done one"]

    todo = client.get("/api/tasks?status=todo", headers=headers).json()
    assert todo["total"] == 3
    due = client.get(f"/api/tasks?due_on_or_before={today.isoformat()}", headers=headers).json()
    assert [t["id"] for t in due["items"]] == [soon["id"]]

    page = client.get("/api/tasks?limit=2&offset=2", headers=headers).json()
    assert page["total"] == 4 and page["limit"] == 2 and page["offset"] == 2
    assert len(page["items"]) == 2
    assert client.get("/api/tasks?limit=0", headers=headers).status_code == 422


def test_empty_list(client, headers):
    body = client.get("/api/tasks", headers=headers).json()
    assert body == {"items": [], "total": 0, "limit": 50, "offset": 0}
