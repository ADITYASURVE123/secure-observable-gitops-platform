#!/usr/bin/env bash
# Jenkins runs in Docker Compose, the monitoring stack runs in Kind. This script bridges them:
#  1. attaches the Jenkins container to Docker's `kind` network (so cluster nodes can reach it)
#  2. creates the Endpoints object (Jenkins' IP) for the selector-less `jenkins` Service
# The Endpoints are environment-specific (an IP), so they are created here and not committed.
set -euo pipefail
cd "$(dirname "$0")/.."

cid="$(docker compose -f ci/docker-compose.yml ps -q jenkins)"
[ -n "$cid" ] || { echo "Jenkins is not running. Run: make jenkins-up" >&2; exit 1; }
docker network inspect kind >/dev/null 2>&1 || { echo "Docker network 'kind' not found. Run: make cluster-up" >&2; exit 1; }
docker network connect kind "$cid" 2>/dev/null || true
ip="$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$cid")"
[ -n "$ip" ] || { echo "Could not determine Jenkins IP on the kind network" >&2; exit 1; }

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -f - <<YAML
apiVersion: v1
kind: Endpoints
metadata:
  name: jenkins
  namespace: monitoring
  labels:
    app.kubernetes.io/name: jenkins
subsets:
  - addresses: [{ ip: ${ip} }]
    ports: [{ name: http, port: 8080 }]
YAML
echo "Jenkins (${ip}:8080) linked. If Jenkins is recreated its IP may change: re-run this script."
