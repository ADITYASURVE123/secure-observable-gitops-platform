#!/usr/bin/env bash
# Incident drill: break the app on purpose, watch the alerts fire, recover, and collect evidence.
#
#   ./scripts/incident-drill.sh full        guided run with pauses for screenshots (recommended)
#   ./scripts/incident-drill.sh baseline    healthy traffic so dashboards have a "before"
#   ./scripts/incident-drill.sh break       inject errors + latency (k6) and kill api containers
#   ./scripts/incident-drill.sh watch       follow alert state until they fire
#   ./scripts/incident-drill.sh recover     remove the fault and wait for alerts to resolve
#   ./scripts/incident-drill.sh evidence    dump kubectl / Alertmanager / Argo CD state to a folder
#   ./scripts/incident-drill.sh summary     print detection / recovery times (for the README + resume)
# Env: NO_PAUSE=1 (skip prompts)  FAIL_RATE=60  DELAY_MS=400  BASELINE_SECONDS=90
set -uo pipefail
cd "$(dirname "$0")/.."

NS=orders
BASE="${BASE_URL:-http://localhost:8080}"
FAIL_RATE="${FAIL_RATE:-60}"
DELAY_MS="${DELAY_MS:-400}"
BASELINE_SECONDS="${BASELINE_SECONDS:-90}"
STATE=.drill-state

[ -f "$STATE" ] && EVID="$(cat "$STATE")" || { EVID="docs/evidence/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$EVID"; echo "$EVID" > "$STATE"; }
mkdir -p "$EVID"

log()   { printf '%s  %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$EVID/timeline.log"; }
mark()  { echo "$1=$(date +%s)" >> "$EVID/metrics.env"; }
pause() { [ "${NO_PAUSE:-0}" = 1 ] || read -r -p "$1  [press Enter to continue] " _; }
prom()  { curl -fsS -G -H 'Host: prometheus.localhost' --data-urlencode "query=$1" "$BASE/api/v1/query"; }
alertmanager() { curl -fsS -H 'Host: alertmanager.localhost' "$BASE/api/v2/alerts?active=true&silenced=false&inhibited=false"; }
states() {  # "OrdersHighErrorRate:firing OrdersPodCrashLooping:pending ..."
  prom 'ALERTS{service="orders"}' | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(" ".join(sorted({r["metric"]["alertname"] + ":" + r["metric"]["alertstate"] for r in d["data"]["result"]})))'
}

preflight() {
  for c in kubectl curl docker python3; do command -v "$c" >/dev/null || { echo "missing: $c" >&2; exit 1; }; done
  curl -fsS "$BASE/api/health" >/dev/null || { echo "App not reachable at $BASE. Is the cluster up and synced?" >&2; exit 1; }
  curl -fsS -H 'Host: prometheus.localhost' "$BASE/-/ready" >/dev/null || { echo "Prometheus not reachable at prometheus.localhost:8080" >&2; exit 1; }
  kubectl -n "$NS" rollout status deploy/api --timeout=60s >/dev/null || { echo "api is not ready" >&2; exit 1; }
}

baseline() {
  preflight
  log "BASELINE: healthy traffic for ${BASELINE_SECONDS}s"
  mark T_BASELINE
  PROFILE=steady DURATION="${BASELINE_SECONDS}s" ./scripts/run-k6.sh >"$EVID/k6-baseline.log" 2>&1
  log "BASELINE done. Alerts now: [$(states)] (expected: none)"
}

break_it() {
  preflight
  log "INCIDENT START: ${FAIL_RATE}% injected errors + ${DELAY_MS}ms added latency, then api containers crashed"
  mark T_START
  docker rm -f drill-k6 >/dev/null 2>&1 || true
  PROFILE=incident DURATION=30m FAIL_RATE="$FAIL_RATE" DELAY_MS="$DELAY_MS" \
    K6_EXTRA_ARGS="--name drill-k6" ./scripts/run-k6.sh >"$EVID/k6-incident.log" 2>&1 </dev/null &
  sleep 5
  log "Traffic generator running (container drill-k6)"

  # Crash containers: each exit raises kube_pod_container_status_restarts_total (3+ in 10m trips the alert).
  for i in 1 2 3 4; do
    pod="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=api -o jsonpath="{.items[$(( (i-1) % 2 ))].metadata.name}" 2>/dev/null)"
    [ -n "$pod" ] || pod="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=api -o jsonpath='{.items[0].metadata.name}')"
    log "Crashing container in $pod (${i}/4)"
    kubectl -n "$NS" exec "$pod" -- python -c \
      "import urllib.request as u; u.urlopen(u.Request('http://127.0.0.1:8000/chaos/crash', method='POST'))" >/dev/null 2>&1 \
      || log "  (exec failed: is CHAOS_ENABLED=true in this overlay?)"
    sleep 30
  done
  one="$(kubectl -n "$NS" get pods -l app.kubernetes.io/name=api -o jsonpath='{.items[0].metadata.name}')"
  log "Deleting pod $one (the 'pod kill': ReplicaSet recreates it, PDB keeps 1 pod serving)"
  kubectl -n "$NS" delete pod "$one" --wait=false >/dev/null
  log "Fault is live. Next: ./scripts/incident-drill.sh watch"
}

watch_alerts() {
  preflight
  log "WATCHING alerts (up to 15 min). Screenshot Prometheus > Alerts, Alertmanager and Slack now."
  local prev="" cur deadline=$(( $(date +%s) + 900 )) seen_err=0 seen_crash=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    cur="$(states || true)"
    if [ "$cur" != "$prev" ]; then log "ALERT STATE: ${cur:-none}"; prev="$cur"; fi
    case "$cur" in *OrdersHighErrorRate:firing*)  [ $seen_err   = 0 ] && { mark T_FIRING_ERRORRATE; seen_err=1; };; esac
    case "$cur" in *OrdersPodCrashLooping:firing*) [ $seen_crash = 0 ] && { mark T_FIRING_CRASHLOOP; seen_crash=1; };; esac
    [ $seen_err = 1 ] && [ $seen_crash = 1 ] && { log "Both key alerts are FIRING"; return 0; }
    sleep 15
  done
  log "Timed out waiting for both alerts. Check traffic: docker logs drill-k6"
}

recover() {
  log "FIX: removing the fault (stop traffic generator, cluster self-heals)"
  mark T_FIX
  docker rm -f drill-k6 >/dev/null 2>&1 || true
  kubectl -n "$NS" rollout status deploy/api --timeout=120s | tee -a "$EVID/timeline.log"
  kubectl -n "$NS" get pods -l app.kubernetes.io/name=api | tee -a "$EVID/timeline.log"
  # Light healthy traffic so rate-based alerts can evaluate back to normal.
  PROFILE=steady DURATION=10m K6_EXTRA_ARGS="--name drill-k6" ./scripts/run-k6.sh >"$EVID/k6-recovery.log" 2>&1 </dev/null &
  log "WAITING for alerts to resolve (up to 20 min; Alertmanager sends RESOLVED to Slack)"
  local deadline=$(( $(date +%s) + 1200 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    cur="$(states || true)"
    if [ -z "$cur" ]; then log "RECOVERED: no orders alerts pending or firing"; mark T_RESOLVED; break; fi
    log "still active: $cur"; sleep 30
  done
  docker rm -f drill-k6 >/dev/null 2>&1 || true
}

evidence() {
  log "Collecting evidence in $EVID"
  kubectl -n "$NS" get pods -o wide                       > "$EVID/pods.txt" 2>&1
  kubectl -n "$NS" get events --sort-by=.lastTimestamp    > "$EVID/events.txt" 2>&1
  kubectl -n "$NS" describe pods -l app.kubernetes.io/name=api > "$EVID/describe-api.txt" 2>&1
  kubectl -n "$NS" logs deploy/api --tail=200             > "$EVID/api-logs.txt" 2>&1
  kubectl -n argocd get applications.argoproj.io          > "$EVID/argocd-apps.txt" 2>&1
  alertmanager                                            > "$EVID/alertmanager-alerts.json" 2>&1
  prom 'ALERTS{service="orders"}'                         > "$EVID/prometheus-ALERTS.json" 2>&1
  prom 'orders:http_errors:ratio_rate5m'                  > "$EVID/error-ratio-now.json" 2>&1
  log "Evidence saved. Add screenshots to docs/images/ following docs/incident-drill.md"
}

summary() {
  [ -f "$EVID/metrics.env" ] || { echo "no metrics yet in $EVID"; return 1; }
  # shellcheck disable=SC1090
  source "$EVID/metrics.env"
  echo "Evidence folder: $EVID"
  [ -n "${T_START:-}" ] && [ -n "${T_FIRING_ERRORRATE:-}" ] && echo "Time to detect (error-rate alert firing):  $(( T_FIRING_ERRORRATE - T_START ))s"
  [ -n "${T_START:-}" ] && [ -n "${T_FIRING_CRASHLOOP:-}" ] && echo "Time to detect (crash-loop alert firing):  $(( T_FIRING_CRASHLOOP - T_START ))s"
  [ -n "${T_FIX:-}" ] && [ -n "${T_RESOLVED:-}" ] && echo "Time to recover (fault removed -> resolved): $(( T_RESOLVED - T_FIX ))s"
}

case "${1:-}" in
  baseline) baseline ;;
  break)    break_it ;;
  watch)    watch_alerts ;;
  recover)  recover ;;
  evidence) evidence ;;
  summary)  summary ;;
  full)
    preflight
    pause "STEP 1 - Open Grafana (http://grafana.localhost:8080) 'Orders API: RED metrics and SLO' and Argo CD. Ready to start healthy baseline traffic?"
    baseline
    pause "SCREENSHOTS 01-02 now (healthy dashboard, Argo CD Synced/Healthy)."
    break_it
    pause "SCREENSHOT 03 now (kubectl get pods showing restarts / CrashLoopBackOff). Then watch alerts."
    watch_alerts
    pause "SCREENSHOTS 04-08 now (Grafana red panels, Prometheus Alerts firing, Alertmanager, Slack FIRING)."
    recover
    pause "SCREENSHOTS 09-10 now (Grafana recovered, Slack RESOLVED)."
    evidence
    summary
    rm -f "$STATE"
    ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
