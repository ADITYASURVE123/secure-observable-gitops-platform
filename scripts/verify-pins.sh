#!/usr/bin/env bash
# Confirms every pinned version still exists upstream BEFORE you spend 20 minutes on a failed install.
# Needs network, docker and helm. Exit code != 0 lists what to bump.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  MISSING %s   -> %s\n' "$1" "$2"; fail=1; }

echo "Container images"
for img in \
  python:3.12.12-slim-bookworm node:22.12.0-alpine3.21 nginxinc/nginx-unprivileged:1.29.1-alpine3.22 \
  postgres:16.6-alpine3.21 jenkins/jenkins:2.541.3-lts-jdk21 docker:27.4.1-dind docker:27.4.1-cli \
  busybox:1.37.0 grafana/k6:1.0.0 kindest/node:v1.35.8; do
  if docker manifest inspect "$img" >/dev/null 2>&1; then ok "$img"; else bad "$img" "edit the tag (grep -rn '${img%%:*}' .)"; fi
done

echo "Helm charts"
chk() { # name url chart version file
  helm repo add "$1" "$2" >/dev/null 2>&1; helm repo update "$1" >/dev/null 2>&1
  if helm show chart "$1/$3" --version "$4" >/dev/null 2>&1; then ok "$3 $4"; else bad "$3 $4" "pick one from: helm search repo $1/$3 --versions | head; edit $5"; fi
}
chk prometheus-community https://prometheus-community.github.io/helm-charts kube-prometheus-stack 81.4.2 argocd/apps/kube-prometheus-stack.yaml
chk sealed-secrets https://bitnami-labs.github.io/sealed-secrets sealed-secrets 2.16.2 argocd/apps/sealed-secrets.yaml
chk aqua https://aquasecurity.github.io/helm-charts/ trivy-operator 0.24.1 argocd/apps/trivy-operator.yaml
chk traefik https://traefik.github.io/charts traefik 39.0.9 Makefile

echo "Upstream manifests / tools"
for url in \
  https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.6/manifests/install.yaml \
  https://github.com/aquasecurity/trivy/releases/download/v0.58.1/trivy_0.58.1_checksums.txt \
  "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.5.0/checksums.txt"; do
  if curl -fsIL "$url" >/dev/null 2>&1; then ok "${url##*/}"; else bad "$url" "bump the version"; fi
done
exit "$fail"
