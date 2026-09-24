from datetime import date, timedelta

import pytest

from tests.conftest import auth_headers, register

TODAY = date.today()


def person(client, username):
    data = register(client)
    headers = auth_headers(data)
    assert client.patch("/api/profile", json={"username": username}, headers=headers).status_code == 200
    return {"id": data["user"]["id"], "email": data["user"]["email"], "h": headers}


@pytest.fixture
def trio(client):
    return person(client, "asha"), person(client, "ben"), person(client, "chen")


def befriend(client, a, b, b_name):
    client.post("/api/social/friends/requests", json={"username": b_name}, headers=a["h"])
    req = client.get("/api/social/friends", headers=b["h"]).json()["incoming"][0]
    assert client.post(f"/api/social/friends/requests/{req['id']}/accept", headers=b["h"]).status_code == 200


# ---- friends


def test_friend_request_flow_and_public_fields_only(client, trio):
    asha, ben, _ = trio
    found = client.get("/api/social/users/BEN", headers=asha["h"]).json()
    assert set(found) == {"id", "display_name", "username"}, "no email or goals leak"
    assert client.get("/api/social/users/nobody", headers=asha["h"]).status_code == 404

    sent = client.post("/api/social/friends/requests", json={"username": "@ben"}, headers=asha["h"])
    assert sent.status_code == 201 and len(sent.json()["outgoing"]) == 1
    dup = client.post("/api/social/friends/requests", json={"username": "ben"}, headers=asha["h"])
    assert dup.status_code == 409
    self_add = client.post("/api/social/friends/requests", json={"username": "asha"}, headers=asha["h"])
    assert self_add.status_code == 422

    req = client.get("/api/social/friends", headers=ben["h"]).json()["incoming"][0]
    assert client.post(f"/api/social/friends/requests/{req['id']}/accept", headers=asha["h"]).status_code == 404
    accepted = client.post(f"/api/social/friends/requests/{req['id']}/accept", headers=ben["h"]).json()
    assert [f["username"] for f in accepted["friends"]] == ["asha"]
    assert client.post("/api/social/friends/requests", json={"username": "ben"}, headers=asha["h"]).status_code == 409

    assert client.delete(f"/api/social/friends/{ben['id']}", headers=asha["h"]).status_code == 204
    assert client.get("/api/social/friends", headers=ben["h"]).json()["friends"] == []


def test_crossed_requests_become_friendship(client, trio):
    asha, ben, _ = trio
    client.post("/api/social/friends/requests", json={"username": "ben"}, headers=asha["h"])
    both = client.post("/api/social/friends/requests", json={"username": "asha"}, headers=ben["h"]).json()
    assert [f["username"] for f in both["friends"]] == ["asha"]


def test_decline(client, trio):
    asha, ben, _ = trio
    client.post("/api/social/friends/requests", json={"username": "ben"}, headers=asha["h"])
    req = client.get("/api/social/friends", headers=ben["h"]).json()["incoming"][0]
    after = client.post(f"/api/social/friends/requests/{req['id']}/decline", headers=ben["h"]).json()
    assert after["incoming"] == [] and after["friends"] == []


# ---- groups + chat


def test_groups_are_invite_only_and_private(client, trio):
    asha, ben, chen = trio
    befriend(client, asha, ben, "ben")
    group = client.post("/api/social/groups", json={"name": "Study Squad"}, headers=asha["h"]).json()
    gid = group["id"]
    assert group["my_role"] == "owner" and group["member_count"] == 1

    not_friend = client.post(f"/api/social/groups/{gid}/members", json={"user_id": chen["id"]}, headers=asha["h"])
    assert not_friend.status_code == 403
    added = client.post(f"/api/social/groups/{gid}/members", json={"user_id": ben["id"]}, headers=asha["h"])
    assert added.status_code == 200 and len(added.json()["members"]) == 2

    # outsiders can't see it, its chat, or its challenges
    assert client.get(f"/api/social/groups/{gid}", headers=chen["h"]).status_code == 404
    assert client.get(f"/api/social/groups/{gid}/messages", headers=chen["h"]).status_code == 404
    assert client.post(f"/api/social/groups/{gid}/messages", json={"body": "hi"}, headers=chen["h"]).status_code == 404
    assert client.get(f"/api/social/groups/{gid}/challenges", headers=chen["h"]).status_code == 404

    # members can't manage
    assert client.patch(f"/api/social/groups/{gid}", json={"name": "x"}, headers=ben["h"]).status_code == 403
    assert client.delete(f"/api/social/groups/{gid}", headers=ben["h"]).status_code == 403
    assert client.delete(f"/api/social/groups/{gid}/members/{asha['id']}", headers=ben["h"]).status_code == 403
    assert client.delete(f"/api/social/groups/{gid}/members/{asha['id']}", headers=asha["h"]).status_code == 409

    # chat
    first = client.post(f"/api/social/groups/{gid}/messages", json={"body": "Library at 5?"}, headers=asha["h"])
    assert first.status_code == 201 and first.json()["mine"] is True
    client.post(f"/api/social/groups/{gid}/messages", json={"body": "Yes!"}, headers=ben["h"])
    thread = client.get(f"/api/social/groups/{gid}/messages", headers=ben["h"]).json()
    assert [m["body"] for m in thread] == ["Library at 5?", "Yes!"]
    assert [m["mine"] for m in thread] == [False, True]
    newer = client.get(
        f"/api/social/groups/{gid}/messages", params={"after": thread[0]["created_at"]}, headers=ben["h"]
    ).json()
    assert [m["body"] for m in newer] == ["Yes!"]
    assert client.post(f"/api/social/groups/{gid}/messages", json={"body": "  "}, headers=ben["h"]).status_code == 422

    # leaving
    assert client.delete(f"/api/social/groups/{gid}/members/{ben['id']}", headers=ben["h"]).status_code == 204
    assert client.get(f"/api/social/groups/{gid}/messages", headers=ben["h"]).status_code == 404
    assert client.get("/api/social/groups", headers=ben["h"]).json() == []


# ---- feed


def test_progress_posts_use_server_numbers_and_respect_visibility(client, trio):
    asha, ben, chen = trio
    befriend(client, asha, ben, "ben")
    client.post("/api/study/sessions", json={"duration_minutes": 95}, headers=asha["h"])
    post = client.post(
        "/api/social/posts",
        json={"kind": "progress", "share": ["study_minutes", "study_streak"], "text": "Good day"},
        headers=asha["h"],
    )
    assert post.status_code == 201
    payload = post.json()["payload"]
    assert payload["study_minutes"] == 95 and payload["study_streak"] == 1
    assert "steps" not in payload, "only the chosen numbers are shared"

    assert len(client.get("/api/social/feed", headers=ben["h"]).json()) == 1
    assert client.get("/api/social/feed", headers=chen["h"]).json() == []
    pid = post.json()["id"]
    assert client.post(f"/api/social/posts/{pid}/like", headers=chen["h"]).status_code == 404
    liked = client.post(f"/api/social/posts/{pid}/like", headers=ben["h"]).json()
    again = client.post(f"/api/social/posts/{pid}/like", headers=ben["h"]).json()
    assert liked["like_count"] == again["like_count"] == 1 and again["liked_by_me"] is True
    assert client.delete(f"/api/social/posts/{pid}/like", headers=ben["h"]).json()["like_count"] == 0
    assert client.delete(f"/api/social/posts/{pid}", headers=ben["h"]).status_code == 404
    assert client.delete(f"/api/social/posts/{pid}", headers=asha["h"]).status_code == 204


def test_post_validation_and_client_cannot_fake_numbers(client, trio):
    asha, _, _ = trio
    h = asha["h"]
    assert client.post("/api/social/posts", json={"kind": "progress", "share": []}, headers=h).status_code == 422
    assert client.post("/api/social/posts", json={"kind": "text", "text": " "}, headers=h).status_code == 422
    faked = client.post(
        "/api/social/posts", json={"kind": "progress", "share": ["steps"], "payload": {"steps": 99999}}, headers=h
    )
    assert faked.status_code == 422
    unearned = client.post(
        "/api/social/posts", json={"kind": "achievement", "achievement_code": "tasks_100"}, headers=h
    )
    assert unearned.status_code == 422


def test_achievement_share_after_earning(client, trio):
    asha, ben, _ = trio
    befriend(client, asha, ben, "ben")
    before = {a["code"]: a for a in client.get("/api/achievements", headers=asha["h"]).json()}
    assert before["first_study"]["earned"] is False
    client.post("/api/study/sessions", json={"duration_minutes": 30}, headers=asha["h"])
    after = {a["code"]: a for a in client.get("/api/achievements", headers=asha["h"]).json()}
    assert after["first_study"]["earned"] is True and after["study_hours_10"]["progress"] == 30
    shared = client.post(
        "/api/social/posts", json={"kind": "achievement", "achievement_code": "first_study"}, headers=asha["h"]
    ).json()
    assert shared["payload"]["title"] == "First step"
    assert client.get("/api/social/feed", headers=ben["h"]).json()[0]["kind"] == "achievement"


def test_group_posts_only_reach_the_group(client, trio):
    asha, ben, chen = trio
    befriend(client, asha, ben, "ben")
    befriend(client, asha, chen, "chen")
    gid = client.post("/api/social/groups", json={"name": "Duo"}, headers=asha["h"]).json()["id"]
    client.post(f"/api/social/groups/{gid}/members", json={"user_id": ben["id"]}, headers=asha["h"])
    client.post("/api/social/posts", json={"kind": "text", "text": "Group only", "group_id": gid}, headers=asha["h"])
    assert [p["body"] for p in client.get("/api/social/feed", headers=ben["h"]).json()] == ["Group only"]
    assert client.get("/api/social/feed", headers=chen["h"]).json() == [], "a friend outside the group can't see it"
    outsider = client.post(
        "/api/social/posts", json={"kind": "text", "text": "sneak", "group_id": gid}, headers=chen["h"]
    )
    assert outsider.status_code == 404


# ---- challenges


def test_challenge_counts_only_participants(client, trio):
    asha, ben, _ = trio
    befriend(client, asha, ben, "ben")
    gid = client.post("/api/social/groups", json={"name": "Squad"}, headers=asha["h"]).json()["id"]
    client.post(f"/api/social/groups/{gid}/members", json={"user_id": ben["id"]}, headers=asha["h"])
    body = {
        "title": "20 sessions",
        "metric": "study_sessions",
        "target": 2,
        "start_date": (TODAY - timedelta(days=1)).isoformat(),
        "end_date": (TODAY + timedelta(days=6)).isoformat(),
    }
    created = client.post(f"/api/social/groups/{gid}/challenges", json=body, headers=asha["h"]).json()
    cid = created["id"]
    assert created["joined"] is True and created["participant_count"] == 1

    for _ in range(2):
        client.post("/api/study/sessions", json={"duration_minutes": 25}, headers=asha["h"])
    client.post("/api/study/sessions", json={"duration_minutes": 25}, headers=ben["h"])

    view = client.get(f"/api/social/challenges/{cid}", headers=ben["h"]).json()
    assert [r["user"]["username"] for r in view["leaderboard"]] == ["asha"], "ben hasn't joined, so he isn't counted"
    assert view["leaderboard"][0]["completed"] is True

    joined = client.post(f"/api/social/challenges/{cid}/join", headers=ben["h"]).json()
    assert joined["participant_count"] == 2 and joined["group_total"] == 3
    left = client.delete(f"/api/social/challenges/{cid}/join", headers=ben["h"]).json()
    assert left["participant_count"] == 1

    bad = dict(body, end_date=(TODAY - timedelta(days=5)).isoformat())
    assert client.post(f"/api/social/groups/{gid}/challenges", json=bad, headers=asha["h"]).status_code == 422
    assert (
        client.post(
            f"/api/social/groups/{gid}/challenges", json=dict(body, metric="gold"), headers=asha["h"]
        ).status_code
        == 422
    )


def test_social_requires_auth(client):
    for path in ("/api/social/friends", "/api/social/groups", "/api/social/feed", "/api/achievements"):
        assert client.get(path).status_code == 401


def test_deleting_account_removes_social_traces(client, trio):
    asha, ben, _ = trio
    befriend(client, asha, ben, "ben")
    client.post("/api/social/posts", json={"kind": "text", "text": "bye"}, headers=asha["h"])
    assert (
        client.post(
            "/api/auth/delete-account", json={"password": "correct-horse-battery"}, headers=asha["h"]
        ).status_code
        == 204
    )
    assert client.get("/api/social/friends", headers=ben["h"]).json()["friends"] == []
    assert client.get("/api/social/feed", headers=ben["h"]).json() == []
