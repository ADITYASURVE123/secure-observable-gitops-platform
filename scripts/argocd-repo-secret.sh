#!/usr/bin/env bash
# ONLY needed if the GitHub repo is private. Registers repo credentials with Argo CD as a
# Secret created straight from ci/.env: nothing is written to Git.
# Tip: for least privilege use a separate read-only token (Contents: Read) instead of the
# read/write token Jenkins uses. Set ARGOCD_GIT_TOKEN to override.
set -euo pipefail
cd "$(dirname "$0")/.."
get() { grep -E "^$1=" ci/.env | cut -d= -f2- ; }

url="$(get GIT_REPO_URL)"; user="$(get GIT_USER)"; token="${ARGOCD_GIT_TOKEN:-$(get GIT_TOKEN)}"
[ -n "$url" ] && [ -n "$user" ] && [ -n "$token" ] || { echo "GIT_REPO_URL/GIT_USER/GIT_TOKEN missing in ci/.env" >&2; exit 1; }

kubectl -n argocd create secret generic repo-orders-platform \
  --from-literal=type=git --from-literal=url="$url" \
  --from-literal=username="$user" --from-literal=password="$token" \
  --dry-run=client -o yaml \
 | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
 | kubectl apply -f -
echo "Registered repository credentials with Argo CD"
