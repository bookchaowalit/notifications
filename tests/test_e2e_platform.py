"""End to end with the real empire-platform (its own throwaway database, in-process HTTP).

Skipped unless empire-platform is installed in the environment (a sibling
checkout: ``uv pip install -e ../platform-empire[dev]``). Proves the contract:
real PDP decisions, executions bound to the operation, audit rows, and graph
ingest of the outbox through the publisher's delegated token.
"""

from __future__ import annotations

import shutil
import tempfile
import uuid
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

pytest.importorskip("platform_api")

from empire_platform.devdb import Cluster, bootstrap, migrate as platform_migrate  # noqa: E402
from empire_platform.devtoken import key_pair, mint  # noqa: E402
from empire_platform.permissions import NOTIFICATIONS_OWNER  # noqa: E402
from platform_api.routes import register  # noqa: E402
from tasks_api.auth import TokenVerifier as PlatformVerifier  # noqa: E402

from solo_notifications.app import create_app  # noqa: E402
from solo_notifications.auth import TokenVerifier  # noqa: E402
from solo_notifications.platform import HttpPlatform  # noqa: E402

ISSUER = "empire-e2e"


@pytest.fixture(scope="module")
def platform_cluster():
    root = Path(tempfile.mkdtemp(prefix="ep-e2e-"))
    cluster = Cluster(root / "data", root / "sock")
    cluster.init()
    cluster.start()
    try:
        bootstrap(cluster)
        platform_migrate(cluster)
        yield cluster
    finally:
        cluster.stop()
        shutil.rmtree(root, ignore_errors=True)


@pytest.fixture(scope="module")
def world(platform_cluster, tmp_path_factory):
    import importlib.util
    import sys

    # empire-platform's own workspace helpers (its tests/conftest.py, loaded under another name).
    path = Path(__import__("empire_platform").__file__).resolve().parents[2] / "tests" / "conftest.py"
    spec = importlib.util.spec_from_file_location("empire_platform_fixtures", path)
    fixtures = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = fixtures  # dataclasses look their module up while the class is created
    spec.loader.exec_module(fixtures)
    add_member, create_workspace, delegate = fixtures.add_member, fixtures.create_workspace, fixtures.delegate

    private, public = key_pair(tmp_path_factory.mktemp("e2e-keys"))
    with platform_cluster.connect("platform_api") as conn:
        ws = create_workspace(conn, f"e2e-{uuid.uuid4().hex[:8]}", list(NOTIFICATIONS_OWNER))
        reader = add_member(conn, ws, "reader", "agent")
        read_only = delegate(conn, ws, ws.owner, reader, ["notifications.notification:read"])
        conn.commit()
    platform_app = FastAPI()
    register(platform_app, connect_platform=lambda: platform_cluster.connect("tasks_api"),
             platform_verifier=PlatformVerifier(public, ISSUER, audience="platform-api"),
             graph_verifier=PlatformVerifier(public, ISSUER, audience="graph-api"))
    http = HttpPlatform("http://localhost", client=TestClient(platform_app, base_url="http://localhost"))
    audiences = ["notifications-api", "platform-api", "graph-api"]

    def bearer(sub, **kwargs):
        return mint(private, sub=sub, ws=ws.id, issuer=ISSUER, audience=audiences, **kwargs)

    return {"ws": ws, "public": public, "http": http, "bearer": bearer, "reader": reader, "read_only": read_only}


@pytest.fixture(scope="module")
def cell(cluster, world):
    app = create_app(lambda: cluster.connect("notifications_api"), TokenVerifier(world["public"], ISSUER),
                     world["http"])
    return TestClient(app)


def test_queue_and_delivery_are_executions_with_audit(cell, world, platform_cluster):
    owner = {"Authorization": f"Bearer {world['bearer'](world['ws'].owner)}"}
    queued = cell.post("/v1/notifications", headers=owner, json={
        "title": "E2E", "message": "hello", "notification_type": "overdue", "dedupe_key": "e2e-key-0001"})
    assert queued.status_code == 201, queued.text
    entry = queued.json()["notification"]["id"]
    assert cell.post("/v1/notifications", headers=owner, json={
        "title": "E2E", "message": "hello", "notification_type": "overdue",
        "dedupe_key": "e2e-key-0001"}).json()["outcome"] == "existing"
    assert cell.post(f"/v1/notifications/{entry}/delivery", headers=owner,
                     json={"outcome": "delivered", "channel": "telegram"}).status_code == 200
    with platform_cluster.connect("postgres") as conn:
        rows = conn.execute(
            "SELECT e.status, a.action FROM platform.audit_events a JOIN platform.executions e ON e.id = a.execution_id"
            " WHERE a.resource_id = %s AND a.service = 'notifications' ORDER BY a.id", (str(entry),)).fetchall()
    assert rows == [("succeeded", "notifications.notification.queued"),
                    ("succeeded", "notifications.notification.delivered")]


def test_read_only_delegation_reads_but_cannot_queue(cell, world):
    reader = {"Authorization": "Bearer " + world["bearer"](world["reader"], delegation=world["read_only"],
                                                          obo=world["ws"].owner)}
    assert cell.get("/v1/notifications", headers=reader).status_code == 200
    assert cell.post("/v1/notifications", headers=reader, json={
        "title": "x", "message": "y", "notification_type": "overdue"}).status_code == 403
