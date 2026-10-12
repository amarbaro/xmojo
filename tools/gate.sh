#!/usr/bin/env bash
# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# The gate: every check passes, the oracle can still fail, and documented code runs. Run inside the pixi env: pixi run gate
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
# every tool must still build against the current API
for t in tools/xmldump.mojo tools/bench.mojo; do
  mojo build -I src "$t" -o .work/gate-build || { echo "FAIL gate: $t does not build"; exit 1; }
done
fail=()
for f in tests/test_*.mojo; do
  mojo run -I src "$f" || fail+=("$f")
done
[ ${#fail[@]} -eq 0 ] || { echo "FAIL gate: ${#fail[@]} test files: ${fail[*]}"; exit 1; }
mojo build -I src tools/xmldump.mojo -o .work/xmldump
python3 tools/oracle.py 2000 1
python3 tools/oracle.py 2000 7
python3 tools/oracle.py 200 1 --negative
python3 tools/check_snippets.py
echo "gate: OK ($(git rev-parse --short HEAD 2>/dev/null || echo no-git))"
