#!/usr/bin/env bash
# Creates the database credentials Secret out-of-band so no password is ever committed.
# Idempotent: an existing Secret is left alone (rotating the password would break the
# already-initialised Postgres volume).
# Phase 5 replaces this with a SealedSecret that IS safe to store in Git.
set -euo pipefail

NAMESPACE="${NAMESPACE:-orders}"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if kubectl -n "$NAMESPACE" get secret orders-db >/dev/null 2>&1; then
  echo "secret/orders-db already exists in namespace $NAMESPACE - leaving it unchanged"
  exit 0
fi

password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
kubectl -n "$NAMESPACE" create secret generic orders-db \
  --from-literal=username=orders \
  --from-literal=password="$password" >/dev/null
echo "created secret/orders-db in namespace $NAMESPACE"
