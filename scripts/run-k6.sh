#!/usr/bin/env bash
# Runs k6 in Docker (nothing to install). Usage: PROFILE=load ./scripts/run-k6.sh
# Linux: host networking reaches localhost:8080. macOS/Windows (Docker Desktop): use host.docker.internal.
set -uo pipefail
cd "$(dirname "$0")/.."
K6_IMAGE="${K6_IMAGE:-grafana/k6:1.0.0}"
if [ "$(uname -s)" = "Linux" ]; then net=(--network host); base="${BASE_URL:-http://localhost:8080}"
else net=(); base="${BASE_URL:-http://host.docker.internal:8080}"; fi

exec docker run --rm -i ${net[@]+"${net[@]}"} \
  -e BASE_URL="$base" -e PROFILE="${PROFILE:-smoke}" -e DURATION="${DURATION:-2m}" \
  -e FAIL_RATE="${FAIL_RATE:-0}" -e DELAY_MS="${DELAY_MS:-0}" \
  ${K6_EXTRA_ARGS:-} \
  -v "$PWD/load-test:/scripts:ro" "$K6_IMAGE" run /scripts/script.js
