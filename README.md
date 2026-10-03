# Secure, Observable GitOps Platform

A small three-tier app (frontend, FastAPI, Postgres) used to demonstrate a production-style
delivery platform: **CI security scanning, GitOps delivery, and observability**, all runnable
on a laptop with Kind.

> Status: **Phase 3 of 7** (CD). The full README (architecture diagram, tool
> choices, incident write-up, screenshots) is completed in the final phase.

## Roadmap

| Phase | Scope | Status |
|------:|-------|--------|
| 1 | Kind cluster, Kustomize manifests, app running locally | done |
| 2 | Jenkins (Docker, JCasC), Jenkinsfile with Trivy gate | done |
| 3 | ArgoCD, app-of-apps, auto-sync + self-heal | done |
| 4 | kube-prometheus-stack, ServiceMonitor, Grafana dashboards | todo |
| 5 | PrometheusRules, Alertmanager to Slack, Sealed Secrets | todo |
| 6 | Trivy Operator, k6, NetworkPolicies, Jenkins health | todo |
| 7 | Incident drill script and screenshot checklist | todo |

## Quick start (Phase 1)

Prerequisites: Docker, [kind](https://kind.sigs.k8s.io/) v0.33+, kubectl, helm 3.

```bash
make cluster-up   # Kind (1 control-plane + 2 workers) + Traefik ingress
make deploy       # build images, load into Kind, create DB secret, apply k8s/overlays/dev
make test         # unit tests, manifest rendering, smoke test
open http://localhost:8080
```

`make teardown` deletes the cluster.

## CI quick start (Phase 2)

```bash
make jenkins-up      # first run creates ci/.env; add REGISTRY_TOKEN and GIT_TOKEN, then run again
make jenkins-lock    # optional but recommended: pin all plugins, then commit ci/plugins.lock.txt
open http://localhost:8081
```

Full guide, token setup and troubleshooting: [docs/ci.md](docs/ci.md).

## CD quick start (Phase 3)

```bash
make argocd-up         # Argo CD v3.3.6 on the cluster
make argocd-bootstrap  # applies the root app; Argo CD then deploys k8s/overlays/staging
make gitops-status
make verify-gitops     # proves Jenkins has no way to deploy
```

Run order, demos and design notes: [docs/gitops.md](docs/gitops.md).

## Layout

```
app/api        FastAPI service (/health, /ready, /metrics, /orders, /fail)
app/frontend   Static UI served by unprivileged nginx, proxies /api/* to the API
k8s/base       Namespace (PSA "restricted"), Postgres, API, frontend, Ingress
k8s/overlays   dev (local images) and staging (GHCR images, edited by CI in Phase 2)
kind/          Cluster config and ingress controller values
scripts/       Secret bootstrap and smoke test
ci/            Jenkins (Dockerfile, compose, JCasC, plugins, Jenkinsfile)
argocd/        Argo CD install, bootstrap root app, app-of-apps children
monitoring/ load-test/ docs/   monitoring and load tests arrive in later phases
```

## Design notes

- **No secrets in Git.** The DB password is generated at deploy time by `scripts/create-secrets.sh`
  (Phase 5 moves it to a Sealed Secret).
- **Hardened workloads.** Non-root users, read-only root filesystems, dropped capabilities,
  seccomp `RuntimeDefault`, and the namespace enforces the Pod Security "restricted" profile.
- **Metrics designed for SLOs.** The latency histogram has a bucket at exactly 0.3s, so the
  "99% of requests under 300ms" SLO can be computed without interpolation.
