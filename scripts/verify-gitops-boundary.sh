#!/usr/bin/env bash
# Evidence that CI cannot deploy: the pipeline has no cluster tooling or credentials,
# and the Jenkins image does not contain them either. Exit code != 0 means the boundary is broken.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

echo "1) Jenkinsfile / JCasC must not reference cluster tooling"
# Comment lines are ignored (they may legitimately explain the GitOps flow).
if cat ci/Jenkinsfile ci/jenkins.yaml | grep -vE '^[[:space:]]*(//|#)' \
   | grep -nEi 'kubectl|helm |kubeconfig|argocd (app|login|sync)'; then
  echo "   FAIL: cluster tooling referenced in CI config"; fail=1
else echo "   ok"; fi

echo "2) Jenkins image must not contain kubectl/helm"
img="$(docker compose -f ci/docker-compose.yml config --images 2>/dev/null | grep gitops-jenkins | head -1 || true)"
if [ -n "$img" ] && docker image inspect "$img" >/dev/null 2>&1; then
  if docker run --rm --entrypoint sh "$img" -c 'command -v kubectl || command -v helm' >/dev/null 2>&1; then
    echo "   FAIL: kubectl/helm found in $img"; fail=1
  else echo "   ok ($img)"; fi
else echo "   skipped (Jenkins image not built yet: run make jenkins-up)"; fi

echo "3) The only Git paths the pipeline edits"
grep -n 'k8s/overlays/staging' ci/Jenkinsfile | sed 's/^/   /'
exit "$fail"
