from prometheus_client import (
    CollectorRegistry,
    Counter,
    Gauge,
    Histogram,
    GCCollector,
    PlatformCollector,
    ProcessCollector,
)

# Buckets include 0.3s on purpose: the SLO is "99% of requests under 300ms", and
# histogram_quantile / bucket-ratio SLO queries are only exact on a bucket boundary.
LATENCY_BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.5, 5.0)


class Metrics:
    """One registry per app instance, so tests can build many apps without duplicate-metric errors."""

    def __init__(self, version: str) -> None:
        self.registry = CollectorRegistry()
        GCCollector(registry=self.registry)
        PlatformCollector(registry=self.registry)
        ProcessCollector(registry=self.registry)

        self.requests = Counter(
            "http_requests_total",
            "HTTP requests handled.",
            ["method", "path", "status"],
            registry=self.registry,
        )
        self.errors = Counter(
            "http_request_errors_total",
            "HTTP requests that ended in a 5xx response.",
            ["method", "path"],
            registry=self.registry,
        )
        self.latency = Histogram(
            "http_request_duration_seconds",
            "HTTP request latency in seconds.",
            ["method", "path"],
            buckets=LATENCY_BUCKETS,
            registry=self.registry,
        )
        self.orders_created = Counter(
            "orders_created_total", "Orders successfully created.", registry=self.registry
        )
        build = Gauge("app_build_info", "Build metadata.", ["version"], registry=self.registry)
        build.labels(version=version).set(1)

    def observe(self, method: str, path: str, status: int, seconds: float) -> None:
        # `path` is the route template (e.g. /orders), never the raw URL,
        # to keep label cardinality bounded.
        self.requests.labels(method, path, str(status)).inc()
        self.latency.labels(method, path).observe(seconds)
        if status >= 500:
            self.errors.labels(method, path).inc()
