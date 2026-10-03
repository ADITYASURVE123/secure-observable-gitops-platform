import time

import pytest
from fastapi.testclient import TestClient

from orders_api.main import create_app
from orders_api.repository import InMemoryRepository


@pytest.fixture()
def client():
    with TestClient(create_app(repo=InMemoryRepository())) as c:
        yield c


def metric_line(client, prefix):
    body = client.get("/metrics").text
    return [line for line in body.splitlines() if line.startswith(prefix)]


def test_health_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_ready_ok_with_working_repo(client):
    assert client.get("/ready").status_code == 200


def test_ready_503_when_db_down():
    repo = InMemoryRepository()
    repo.ping = lambda: False
    with TestClient(create_app(repo=repo)) as c:
        assert c.get("/ready").status_code == 503


def test_create_and_list_orders(client):
    created = client.post("/orders", json={"item": "anchor chain", "quantity": 3})
    assert created.status_code == 201
    listed = client.get("/orders").json()
    assert listed[0]["item"] == "anchor chain"
    assert listed[0]["quantity"] == 3


@pytest.mark.parametrize("payload", [{"item": "", "quantity": 1}, {"item": "x", "quantity": 0}, {"item": "x"}])
def test_invalid_order_rejected(client, payload):
    assert client.post("/orders", json=payload).status_code == 422


def test_fail_rate_100_always_500(client):
    assert all(client.get("/fail?rate=100").status_code == 500 for _ in range(5))


def test_fail_rate_0_never_fails(client):
    assert all(client.get("/fail?rate=0").status_code == 200 for _ in range(5))


@pytest.mark.parametrize("rate", ["-1", "101", "abc"])
def test_fail_rate_validated(client, rate):
    assert client.get(f"/fail?rate={rate}").status_code == 422


def test_request_counter_increments(client):
    client.get("/health")
    client.get("/health")
    line = metric_line(client, 'http_requests_total{method="GET",path="/health",status="200"}')
    assert line and line[0].endswith(" 2.0")


def test_error_counter_counts_5xx(client):
    client.get("/fail?rate=100")
    line = metric_line(client, 'http_request_errors_total{method="GET",path="/fail"}')
    assert line and line[0].endswith(" 1.0")


def test_latency_histogram_has_slo_bucket(client):
    client.get("/health")
    assert metric_line(client, 'http_request_duration_seconds_bucket{le="0.3",method="GET",path="/health"}')


def test_unknown_paths_do_not_explode_label_cardinality(client):
    client.get("/does-not-exist-1")
    client.get("/does-not-exist-2")
    assert metric_line(client, 'http_requests_total{method="GET",path="unmatched",status="404"}')


def test_metrics_endpoint_is_not_self_counted(client):
    client.get("/metrics")
    assert not metric_line(client, 'http_requests_total{method="GET",path="/metrics"')


def test_chaos_endpoint_absent_by_default(client):
    assert client.post("/chaos/crash").status_code == 404


def test_chaos_crash_calls_exit_when_enabled(monkeypatch):
    monkeypatch.setenv("CHAOS_ENABLED", "true")
    calls = []
    app = create_app(repo=InMemoryRepository(), exit_fn=calls.append)
    with TestClient(app) as c:
        assert c.post("/chaos/crash").status_code == 202
        deadline = time.time() + 3
        while not calls and time.time() < deadline:
            time.sleep(0.05)
    assert calls == [1]
