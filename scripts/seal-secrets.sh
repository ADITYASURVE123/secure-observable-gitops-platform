#!/usr/bin/env bash
# Turns your Slack incoming-webhook URL into a SealedSecret that is SAFE to commit.
# Requires: the sealed-secrets controller running in the cluster, and the `kubeseal` CLI
# (brew install kubeseal, or https://github.com/bitnami-labs/sealed-secrets/releases).
# The webhook is read from $SLACK_WEBHOOK_URL or typed silently; it is never echoed or written
# anywhere except inside the encrypted output.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v kubeseal >/dev/null || { echo "kubeseal not found. Install it first (see docs/EXECUTION_GUIDE.md)." >&2; exit 1; }
kubectl -n sealed-secrets get deploy sealed-secrets-controller >/dev/null 2>&1 \
  || { echo "sealed-secrets controller not running yet. Run: make argocd-bootstrap and wait for the app to be Healthy." >&2; exit 1; }

url="${SLACK_WEBHOOK_URL:-}"
if [ -z "$url" ]; then read -r -s -p "Slack incoming webhook URL (input hidden): " url; echo; fi
case "$url" in https://hooks.slack.com/*) ;; *) echo "That does not look like a Slack webhook URL." >&2; exit 1 ;; esac

out=monitoring/alertmanager-slack.sealedsecret.yaml
kubectl -n monitoring create secret generic alertmanager-slack \
  --from-literal=url="$url" --dry-run=client -o yaml \
 | kubeseal --controller-name sealed-secrets-controller --controller-namespace sealed-secrets \
            --format yaml > "$out"
unset url

if ! grep -q 'alertmanager-slack.sealedsecret.yaml' monitoring/kustomization.yaml; then
  sed -i.bak '/^  - rules\/orders-alerts.yaml/a\  - alertmanager-slack.sealedsecret.yaml' monitoring/kustomization.yaml
  rm -f monitoring/kustomization.yaml.bak
fi
echo "Wrote $out and registered it in monitoring/kustomization.yaml."
echo "Next: git add monitoring && git commit -m 'feat(monitoring): add sealed Slack webhook' && git push"
echo "Argo CD will apply it; Alertmanager starts as soon as the Secret exists."
