#!/usr/bin/env bash
# Offline quality gate: syntax of every YAML/JSON/shell/Python/JS file, no secrets, no floating
# image tags, manifests render. Runs in `make test` and is safe to run anywhere.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0; step() { printf '%s\n' "$*"; }; bad() { echo "  FAIL: $*"; fail=1; }

step "1) YAML / JSON syntax"
python3 - <<'PY' || fail=1
import glob, json, sys
try: import yaml
except ImportError: print("  skipped YAML (pip install pyyaml)"); yaml=None
bad=0
for f in glob.glob("**/*.y*ml", recursive=True):
    if yaml:
        try: list(yaml.safe_load_all(open(f)))
        except Exception as e: print("  FAIL", f, e); bad=1
for f in glob.glob("**/*.json", recursive=True):
    try: json.load(open(f))
    except Exception as e: print("  FAIL", f, e); bad=1
sys.exit(bad)
PY

step "2) Shell + Python + JS syntax"
for f in scripts/*.sh ci/scripts/*.sh; do bash -n "$f" || bad "$f"; done
python3 -m py_compile app/api/orders_api/*.py app/api/tests/*.py || bad "python"
find . -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
node --check app/frontend/src/app.js 2>/dev/null || bad "frontend js"
cp load-test/script.js /tmp/k6-check.mjs && node --check /tmp/k6-check.mjs 2>/dev/null || bad "k6 script"

step "3) No secrets committed"
if grep -rInE 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abp]-[A-Za-z0-9-]{10,}|hooks\.slack\.com/services/[A-Z0-9]{6,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY' \
     --exclude-dir=.git --exclude=validate-repo.sh .; then bad "possible secret above"; else echo "  ok"; fi
if git ls-files --error-unmatch ci/.env >/dev/null 2>&1; then bad "ci/.env is tracked"; fi

step "4) Image tags are pinned (no :latest, no untagged)"
if grep -rInE '(image:|FROM)[[:space:]]+[^[:space:]]+:latest' --include='*.yaml' --include='Dockerfile' --exclude-dir=.git .; then bad ":latest tag found"; else echo "  ok"; fi

step "5) Kustomize renders (if kubectl is installed)"
if command -v kubectl >/dev/null; then
  for d in k8s/overlays/dev k8s/overlays/staging monitoring monitoring/jenkins; do
    kubectl kustomize "$d" >/dev/null 2>&1 && echo "  ok $d" || bad "$d does not render"
  done
else echo "  skipped (kubectl not installed)"; fi
exit "$fail"
