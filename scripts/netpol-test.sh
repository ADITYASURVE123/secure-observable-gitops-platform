#!/usr/bin/env bash
# Proves the NetworkPolicies are ENFORCED, not just accepted: a pod outside the orders namespace
# must NOT be able to reach Postgres. If it can, your CNI ignores NetworkPolicy.
set -euo pipefail
echo "Trying to reach postgres.orders:5432 from namespace 'default' (expect: blocked)..."
if kubectl run np-test --rm -i --restart=Never --image=busybox:1.37.0 -n default --quiet \
     --command -- sh -c 'nc -z -w 3 postgres.orders.svc.cluster.local 5432' >/dev/null 2>&1; then
  echo "FAIL: connection succeeded. NetworkPolicy is not enforced by this CNI." >&2
  echo "      Install Calico/Cilium on Kind (see docs/EXECUTION_GUIDE.md, Troubleshooting)." >&2
  exit 1
fi
echo "OK: connection blocked, NetworkPolicy is enforced."
