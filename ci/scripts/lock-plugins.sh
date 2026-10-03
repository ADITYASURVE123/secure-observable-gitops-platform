#!/usr/bin/env bash
# Resolves plugins.txt (plugins + all dependencies) to exact versions and writes plugins.lock.txt.
# Run once, commit the result; after that every Jenkins image build installs the same versions.
set -euo pipefail
cd "$(dirname "$0")/.."

image="gitops-jenkins:lockgen"
[ -f plugins.lock.txt ] && mv plugins.lock.txt plugins.lock.txt.bak   # build from plugins.txt only
trap '[ -f plugins.lock.txt.bak ] && [ ! -s plugins.lock.txt ] && mv plugins.lock.txt.bak plugins.lock.txt || rm -f plugins.lock.txt.bak' EXIT

docker build -t "$image" -f Dockerfile .

docker run --rm -i --entrypoint bash "$image" -s <<'INNER' | sort > plugins.lock.txt
set -eu
manifest() {
  if command -v unzip >/dev/null 2>&1; then unzip -p "$1" META-INF/MANIFEST.MF
  else d="$(mktemp -d)"; (cd "$d" && jar xf "$1" META-INF/MANIFEST.MF && cat META-INF/MANIFEST.MF); fi
}
for f in /usr/share/jenkins/ref/plugins/*.jpi; do
  mf="$(manifest "$f" | tr -d '\r' | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n //g')"
  name="$(printf '%s\n' "$mf" | sed -n 's/^Short-Name: //p')"
  ver="$(printf '%s\n' "$mf" | sed -n 's/^Plugin-Version: //p')"
  echo "${name}:${ver}"
done
INNER

echo "Wrote ci/plugins.lock.txt ($(wc -l < plugins.lock.txt) plugins). Commit it."
