# Execution guide: from zero to a running platform

> **Want to run it on AWS?** Follow [AWS_DEPLOYMENT_GUIDE.md](AWS_DEPLOYMENT_GUIDE.md) (EC2 + Kind, or Amazon EKS, region `ap-south-1`).
> It reuses the steps below and tells you exactly what changes. This guide covers running on your own computer.

Follow the steps in order. Every step has a **check** so you know it worked before moving on.
Total time: about 60-90 minutes the first time (image pulls dominate).

## 0. Requirements

| Tool | Version | Notes |
|---|---|---|
| Docker (Desktop or Engine) | 24+ | Give it **at least 4 CPUs and 10 GB RAM** (Docker Desktop > Settings > Resources) |
| kind | v0.33+ | https://kind.sigs.k8s.io |
| kubectl | 1.33+ | |
| helm | 3.x | |
| kubeseal | matches controller 0.27.x | `brew install kubeseal` or the GitHub releases page |
| git, make, curl, python3 | any recent | |
| A Slack workspace (optional) | | Create an *Incoming Webhook* for a channel to see alerts in Slack |

Free host ports: **8080, 8443, 8081**. On Linux, `*.localhost` resolves automatically in browsers and curl (if not, add
`127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost alertmanager.localhost` to `/etc/hosts`).

Unzip the project, then:

```bash
cd secure-observable-gitops-platform
git log --oneline | head -3        # history is included
```

## 1. Put the code on GitHub (Argo CD and Jenkins read from it)

1. Create an **empty** repository named `secure-observable-gitops-platform` under `ADITYASURVE123`. Public is simplest
   (a private repo works too, see step 7).
2. Push:
   ```bash
   git remote add origin https://github.com/ADITYASURVE123/secure-observable-gitops-platform.git
   git push -u origin main
   ```
If you use another repo name or account, search and replace `ADITYASURVE123/secure-observable-gitops-platform` and `adityasurve123`
(lowercase, for GHCR) across the repo, and set `GIT_REPO_URL` in `ci/.env` later.

## 2. Verify versions (30 seconds)

```bash
make verify-pins
```
**Check:** everything says `ok`. If something says `MISSING`, the message tells you which file to edit and how to list valid versions.
Then `make validate`: offline syntax/secret/pin checks should pass.

## 3. Create the two tokens

- **Registry token** (GHCR): GitHub > Settings > Developer settings > Personal access tokens (classic) > scope `write:packages`.
  For Docker Hub instead: an access token with Read & Write, and set `REGISTRY=docker.io`, `REGISTRY_NAMESPACE=adityasurve`,
  `REGISTRY_USER=adityasurve` in `ci/.env`.
- **Git token**: fine-grained PAT, only this repo, **Contents: Read and write**.

Never paste them in chat or commit them. They go only into `ci/.env` (git-ignored).

## 4. Cluster

```bash
make cluster-up
kubectl get nodes                  # 3 nodes Ready
kubectl -n traefik get pods        # traefik Running
```

## 5. (Optional) Sanity-check the app locally without GitOps

```bash
make deploy                        # builds images, loads into Kind, deploys the dev overlay
make test                          # unit tests in Docker, manifests render, smoke test
open http://localhost:8080
make undeploy-dev                  # IMPORTANT before step 8: Argo CD must own the namespace
```

## 6. Jenkins (CI)

```bash
make jenkins-up                    # first run creates ci/.env and asks for the two tokens
$EDITOR ci/.env                    # paste REGISTRY_TOKEN and GIT_TOKEN
make jenkins-up                    # builds the image (downloads Trivy/kustomize), starts Jenkins + DinD
make jenkins-lock                  # pins every plugin -> ci/plugins.lock.txt
git add ci/plugins.lock.txt && git commit -m "build(ci): pin Jenkins plugins" && git push
make urls
```
Open http://localhost:8081, log in as `admin` (password: `JENKINS_ADMIN_PASSWORD` in `ci/.env`), open **orders-platform**, **Build Now**.

**Check:** all 6 stages green; "Build Artifacts" contains `trivy-*.json`, `sbom-*.cdx.json`; a commit
`chore(release): deploy b1-xxxxxxxx to staging [skip ci]` appears on GitHub. Then:
```bash
git pull --rebase                  # get Jenkins' release commit
```
Make the packages **public**: GitHub > your profile > Packages > `orders-api` and `orders-frontend` > Package settings > Change visibility.

If **Trivy fails** the build, that is the gate doing its job: open the JSON report, bump the flagged base image/dependency, push, rebuild.

## 7. Argo CD

```bash
make argocd-up
make argocd-repo-creds             # ONLY if the GitHub repo is private
make argocd-password               # note it; UI: http://argocd.localhost:8080 (admin)
```

## 8. Bootstrap GitOps (this deploys everything else)

```bash
make argocd-bootstrap
make gitops-status
```
Argo CD now installs: the app, Sealed Secrets, kube-prometheus-stack, Trivy Operator and monitoring config, in order
(sync-waves). Give it 5-10 minutes.

**Check:** `make gitops-status` shows `root`, `orders-staging`, `sealed-secrets`, `kube-prometheus-stack`, `trivy-operator`,
`monitoring-config` as **Synced / Healthy**. Then:
```bash
make smoke                         # app works through the ingress
make verify-gitops                 # Jenkins has no way to deploy
make netpol-test                   # NetworkPolicies are enforced
make trivy-report                  # in-cluster scan results (appear after a few minutes)
```

## 9. Slack alerts (Sealed Secret)

1. Create a Slack Incoming Webhook (Slack > Apps > Incoming Webhooks > pick a channel).
2. ```bash
   make seal-secrets               # paste the webhook URL when asked (input is hidden)
   git add monitoring && git commit -m "feat(monitoring): add sealed Slack webhook" && git push
   ```
Argo CD applies it within about a minute and Alertmanager starts. The encrypted file is safe to commit.
(No Slack? Skip this; alerts still show in Alertmanager at http://alertmanager.localhost:8080.)

## 10. Look around

```bash
make urls
make grafana-password
```
Grafana > Dashboards > **Orders** folder > "Orders API: RED metrics and SLO". Generate traffic:
```bash
make load-test PROFILE=load        # or: steady | smoke
```

## 11. Incident drill (the screenshots)

```bash
make drill
```
Follow the prompts and the checklist in [incident-drill.md](incident-drill.md). Afterwards `make drill-summary`, add screenshots to
`docs/images/`, fill the numbers in `README.md` and `RESUME.md`, commit and push.

## 12. (Optional) Jenkins build health in Grafana

```bash
make jenkins-monitor-up            # links Jenkins into the Kind network, adds scrape + dashboard + 2 alerts
```

## 13. Clean up

```bash
make jenkins-down                  # keeps Jenkins data volumes
make teardown                      # deletes the Kind cluster
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `orders-staging` pods `ImagePullBackOff` | Jenkins has not released yet, or the GHCR packages are private. Run a build; make packages public |
| Argo CD app `OutOfSync` / "repository not found" | Repo is private: `make argocd-repo-creds`; or the repo URL differs from the one in `argocd/` |
| `monitoring-config` fails with "no matches for kind ServiceMonitor" | CRDs not installed yet; it retries automatically, wait for `kube-prometheus-stack` to be Healthy |
| Alertmanager pod stuck `ContainerCreating` | Secret `alertmanager-slack` missing: run step 9 (or temporarily create it by hand with a dummy `url`) |
| `*.localhost` does not open | Add the hosts to `/etc/hosts` (see step 0) |
| `make netpol-test` says NOT enforced | Your Kind CNI ignores NetworkPolicy. Install Calico: create the cluster with `networking.disableDefaultCNI: true` and apply Calico, then redo bootstrap |
| Port 8080/8081 in use | Free the port or change `hostPort` in `kind/kind-config.yaml` / `ci/docker-compose.yml` |
| Jenkins plugin install fails | `rm ci/plugins.lock.txt && make jenkins-lock` to re-resolve |
| Grafana dashboard empty | Generate traffic (`make load-test`), check Prometheus > Status > Targets has `api` UP |
| k6 cannot reach the app on macOS | The script uses `host.docker.internal` automatically; check Docker Desktop is running |
