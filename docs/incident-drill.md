# Incident drill: problem, alert, fix (with evidence)

**Goal:** prove the platform detects and survives a real failure, and capture screenshots for the README.

## Prerequisites
Everything is deployed and healthy (see `docs/EXECUTION_GUIDE.md`), and `make seal-secrets` was done if you want Slack messages.
Check: `make gitops-status` shows all apps `Synced/Healthy`; Grafana dashboard shows data.

## Run it

```bash
make drill            # guided run, pauses at each screenshot point (about 25-30 min)
# or step by step:
./scripts/incident-drill.sh baseline | break | watch | recover | evidence | summary
```

What it does:
1. **Baseline**: 90s of healthy traffic (k6).
2. **Break**: k6 injects 60% HTTP 500s and 400ms latency through `/api/fail`; four container crashes via the env-gated
   `/chaos/crash` hook (real restarts), then deletes a pod (the "pod kill").
3. **Detect**: waits for `OrdersHighErrorRate` and `OrdersPodCrashLooping` to fire (latency/SLO alerts usually follow).
4. **Fix**: stops the fault; the cluster is already self-healed (ReplicaSet replaced the pod, PDB kept one replica serving).
5. **Verify**: waits until alerts resolve; Slack receives RESOLVED.
6. **Evidence**: `docs/evidence/<timestamp>/` gets `timeline.log`, kubectl state, Alertmanager JSON, Argo CD status, and detect/recover times.

## Screenshot checklist
Save as PNG in `docs/images/` using exactly these names, then they appear in the README.

| # | File name | What to capture | When |
|--:|---|---|---|
| 01 | `01-grafana-healthy.png` | Grafana "Orders API: RED metrics and SLO": green stats, SLO >= 99% | after baseline |
| 02 | `02-argocd-synced.png` | Argo CD apps list: all Synced / Healthy | after baseline |
| 03 | `03-pods-crashloop.png` | `kubectl -n orders get pods` showing RESTARTS / CrashLoopBackOff | during break |
| 04 | `04-grafana-incident.png` | Grafana: error rate spike, p95 above red 300ms line, SLO panel red | alerts firing |
| 05 | `05-prometheus-alerts.png` | Prometheus > Alerts: Orders* alerts in FIRING | alerts firing |
| 06 | `06-alertmanager.png` | Alertmanager UI with the active alerts | alerts firing |
| 07 | `07-slack-firing.png` | Slack channel message "[FIRING] OrdersHighErrorRate" with runbook link | alerts firing |
| 08 | `08-argocd-selfheal.png` | Argo CD application tree during the pod replacement (optional) | during break |
| 09 | `09-grafana-recovered.png` | Grafana back to normal after the fix | after recover |
| 10 | `10-slack-resolved.png` | Slack "[RESOLVED]" message | after recover |
| 11 | `11-jenkins-pipeline.png` | Jenkins stage view, all stages green, archived `trivy-*.json` | any time |
| 12 | `12-trivy-gate-fail.png` | (optional) a build failed by the Trivy gate with the report | any time |
| 13 | `13-trivy-operator.png` | `make trivy-report` output (in-cluster scan results) | any time |

Tips: use the Grafana time range "Last 30 minutes", hide tokens/URLs (Slack webhook is never shown), and include the browser URL bar.

## After the drill
```bash
./scripts/incident-drill.sh summary     # prints detect/recover seconds: put them in README + resume
git add docs && git commit -m "docs: add incident drill evidence" && git push
```

## Post-incident review template
| Field | Value |
|---|---|
| Start / detected / resolved (UTC) | from `timeline.log` |
| Impact | error rate peak, SLO budget consumed (from the dashboard) |
| Detection | alert names, time to detect |
| Root cause | (drill) injected faults |
| Fix | stop the fault; Kubernetes self-healed; no manual changes (GitOps) |
| Follow-ups | e.g. add readiness gating on error budget, add a canary |
