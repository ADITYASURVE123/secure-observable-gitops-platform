import asyncio
import json
import logging
import random
import time
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException, Query, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from .config import Settings
from .metrics import Metrics
from .repository import OrderRepository, PostgresRepository

log = logging.getLogger("orders_api")


class OrderIn(BaseModel):
    item: str = Field(min_length=1, max_length=100)
    quantity: int = Field(ge=1, le=1000)


class OrderOut(OrderIn):
    id: int
    created_at: datetime


def create_app(repo: OrderRepository | None = None) -> FastAPI:
    settings = Settings.from_env()
    metrics = Metrics(version=settings.version)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if getattr(app.state, "repo", None) is None:
            app.state.repo = PostgresRepository(settings.conninfo())
        app.state.repo.init_schema()
        yield
        app.state.repo.close()

    app = FastAPI(title="Orders API", version=settings.version, lifespan=lifespan)
    app.state.repo = repo

    @app.middleware("http")
    async def observe(request: Request, call_next):
        # Scrapes would otherwise dominate (and skew) the request metrics.
        if request.url.path == "/metrics":
            return await call_next(request)
        start = time.perf_counter()
        status = 500  # if call_next raises, this is what the client effectively sees
        try:
            response = await call_next(request)
            status = response.status_code
            return response
        finally:
            elapsed = time.perf_counter() - start
            route = request.scope.get("route")
            path = route.path if route else "unmatched"
            metrics.observe(request.method, path, status, elapsed)
            log.info(
                json.dumps(
                    {
                        "event": "request",
                        "method": request.method,
                        "path": request.url.path,
                        "status": status,
                        "duration_ms": round(elapsed * 1000, 1),
                    }
                )
            )

    @app.get("/health")
    def health() -> dict:
        """Liveness: the process is up. Deliberately does not touch the DB,
        so a database outage never causes Kubernetes to restart healthy API pods."""
        return {"status": "ok", "version": settings.version}

    @app.get("/ready")
    def ready(request: Request, response: Response) -> dict:
        """Readiness: can this pod serve traffic (i.e. reach Postgres)?"""
        ok = request.app.state.repo.ping()
        if not ok:
            response.status_code = 503
        return {"status": "ready" if ok else "db_unavailable"}

    @app.get("/metrics", include_in_schema=False)
    def prometheus_metrics() -> Response:
        return Response(generate_latest(metrics.registry), media_type=CONTENT_TYPE_LATEST)

    @app.get("/orders", response_model=list[OrderOut])
    def list_orders(request: Request, limit: int = Query(20, ge=1, le=100)):
        return request.app.state.repo.list_orders(limit)

    @app.post("/orders", response_model=OrderOut, status_code=201)
    def create_order(order: OrderIn, request: Request):
        row = request.app.state.repo.create_order(order.item, order.quantity)
        metrics.orders_created.inc()
        return row

    @app.get("/fail")
    async def fail(
        rate: float = Query(0, ge=0, le=100, description="Percent of calls that return HTTP 500"),
        delay_ms: int = Query(0, ge=0, le=5000, description="Artificial latency, for p95 alert tests"),
    ) -> dict:
        """Fault injection for the incident drill. Not a security boundary:
        in a real system this would be disabled or auth-gated outside non-prod."""
        if delay_ms:
            await asyncio.sleep(delay_ms / 1000)
        if random.random() * 100 < rate:  # noqa: S311 - not security-sensitive
            raise HTTPException(status_code=500, detail="injected failure")
        return {"injected": False, "rate": rate}

    return app


logging.basicConfig(level=logging.INFO, format="%(message)s")
app = create_app()
