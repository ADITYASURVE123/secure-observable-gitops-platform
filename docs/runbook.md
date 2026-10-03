# Runbook

Every alert links here. Each section: what it means, how to confirm, how to fix.
Useful URLs (local): Grafana http://grafana.localhost:8080, Prometheus http://prometheus.localhost:8080,
Alertmanager http://alertmanager.localhost:8080, Argo CD http://argocd.localhost:8080.

## OrdersPodCrashLooping
**Meaning:** an `orders` container restarted 3+ times in 10 minutes (or is in CrashLoopBackOff).
**Confirm:** `kubectl -n orders get pods` (RESTARTS column), `kubectl -n orders describe pod <pod>` (Last State, Reason, Exit Code), `kubectl -n orders logs <pod> --previous`.
**Common causes and fixes:**
- Bad release (new image crashes on start): revert the release commit in Git (`git revert <sha>`); Argo CD rolls back.
- DB unreachable or wrong credentials: check `kubectl -n orders get secret orders-db`, Postgres pod health, NetworkPolicies.
- OOMKilled: raise the memory limit in `k8s/base/api.yaml`, commit, let Argo CD sync.
- Drill: `/chaos/crash` was invoked. Stop the drill; restarts age out of the 10-minute window.
**Do not** `kubectl edit` to fix it: Argo CD self-heal will revert manual changes. Fix it in Git.

## OrdersHighErrorRate
**Meaning:** more than 5% of API requests returned 5xx for 5 minutes.
**Confirm:** Grafana > Orders API dashboard > Errors panel and "Request volume by status"; `kubectl -n orders logs deploy/api | grep '"status": 5'`.
**Fix:** identify the failing route (dashboard "Rate by route"). If it followed a release, revert in Git. If it is the DB, check `/ready` and Postgres. If it is injected traffic (`/fail?rate=`), stop the load generator.

## OrdersHighLatencyP95
**Meaning:** p95 latency above 300ms for 5 minutes.
**Confirm:** Grafana > Duration panel; check CPU throttling and DB latency.
**Fix:** scale (`replicas` in Git), optimise the slow route, or investigate Postgres. Check recent releases first.

## OrdersLatencySLOFastBurn
**Meaning:** the 99% < 300ms SLO is burning error budget at 14.4x the sustainable rate in both the 5m and 1h windows (about 2 days to exhaust a 30-day budget).
**Fix:** treat as an incident: same investigation as OrdersHighLatencyP95, but escalate and consider rolling back the latest release.

## OrdersApiNoTargets
**Meaning:** Prometheus has no healthy `api` target for 5 minutes.
**Confirm:** `kubectl -n orders get pods,svc,endpoints`; Prometheus > Status > Targets; check the ServiceMonitor selector and the NetworkPolicy allowing `monitoring` -> api:8000.
**Fix:** typically images not pulled yet (`ImagePullBackOff`: package not public, or Jenkins has not released yet) or a failing readiness probe.

## JenkinsDown
**Meaning:** Prometheus cannot scrape Jenkins.
**Fix:** `make jenkins-up`; if the container IP changed, `make jenkins-monitor-up`; confirm the Jenkins Prometheus plugin is installed and `/prometheus/` responds.

## JenkinsLastBuildFailed
**Meaning:** the latest `orders-platform` build failed for 10+ minutes.
**Fix:** open the build; if the Trivy stage failed, read `reports/trivy-*.json` (archived artifact), upgrade the dependency/base image, or record a justified, expiring entry in `.trivyignore`.
