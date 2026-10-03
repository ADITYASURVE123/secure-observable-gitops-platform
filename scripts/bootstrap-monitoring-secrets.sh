#!/usr/bin/env bash
# Creates the Grafana admin Secret out-of-band (random password, never in Git) so the Grafana
# chart can reference it via `existingSecret`. Idempotent.
set -euo pipefail
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
if kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  echo "secret/grafana-admin already exists - leaving it unchanged"; exit 0
fi
pw="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password="$pw" >/dev/null
echo "created secret/grafana-admin (read it with: make grafana-password)"
