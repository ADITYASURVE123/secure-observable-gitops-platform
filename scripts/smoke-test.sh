#!/usr/bin/env bash
# Black-box check against the running cluster through the ingress.
set -euo pipefail
BASE="${BASE_URL:-http://localhost:8080}"

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "frontend:"; curl -fsS "$BASE/healthz" >/dev/null || fail "frontend /healthz"
echo "api health:"; curl -fsS "$BASE/api/health" | tee /dev/stderr >/dev/null
echo; echo "api readiness (DB):"; curl -fsS "$BASE/api/ready" >/dev/null || fail "api /ready"
echo "create order:"
curl -fsS -X POST "$BASE/api/orders" -H 'Content-Type: application/json' \
  -d '{"item":"smoke-test","quantity":1}' >/dev/null || fail "POST /orders"
echo "list orders:"; curl -fsS "$BASE/api/orders" | grep -q smoke-test || fail "order not persisted"
echo "metrics hidden from ingress:"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/metrics")" = "404" ] || fail "/api/metrics is exposed"
echo "OK: all smoke checks passed"
