#!/usr/bin/env bash
# Builds dist/<project>.zip: the full working tree INCLUDING git history, excluding secrets/state.
set -euo pipefail
cd "$(dirname "$0")/.."
name="$(basename "$PWD")"; out="dist/${name}.zip"; mkdir -p dist; rm -f "$out"
python3 - "$name" "$out" <<'PY'
import os, sys, zipfile
name, out = sys.argv[1], sys.argv[2]
skip_dirs = {"dist", "__pycache__", "node_modules", ".pytest_cache", ".venv"}
skip_files = {".drill-state"}
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for f in files:
            if f in skip_files or (f == ".env") or f.endswith((".pem", ".key", ".pyc")): continue
            p = os.path.join(root, f)
            z.write(p, os.path.join(name, os.path.relpath(p, ".")))
print("wrote", out)
PY
ls -lh "$out"
