#!/usr/bin/env bash
# Creates ci/.env with a random Jenkins admin password, then checks the two tokens you must
# supply yourself. Safe to re-run: an existing .env is never overwritten.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  cp .env.example .env
  pw="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  sed -i.bak "s|^JENKINS_ADMIN_PASSWORD=.*|JENKINS_ADMIN_PASSWORD=${pw}|" .env && rm -f .env.bak
  chmod 600 .env
  echo "Created ci/.env (mode 600) with a generated Jenkins admin password."
fi

missing=0
for key in REGISTRY_TOKEN GIT_TOKEN; do
  value="$(grep -E "^${key}=" .env | cut -d= -f2- || true)"
  if [ -z "$value" ]; then
    echo "ERROR: ${key} is empty. Edit ci/.env (see docs/ci.md for how to create the token)." >&2
    missing=1
  fi
done
exit "$missing"
