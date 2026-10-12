#!/usr/bin/env bash
# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# Interleaved A/B of tools/bench.mojo binaries on a busy box: median cycles and instructions (user
# space) over REPS alternating runs. Usage: tools/ab.sh "BENCH ARGS" REPS BIN...
# e.g. tools/ab.sh "wide 300000" 11 old new; tools/ab.sh "file x.atom 2000" 9 old new
set -euo pipefail
read -ra args <<< "$1"; reps=$2; shift 2
out=$(mktemp -d "${TMPDIR:-.work}/ab.XXXX")
for ((r = 0; r < reps; r++)); do
  for b in "$@"; do
    perf stat -x, -e cycles:u,instructions:u "$b" "${args[@]}" 2>>"$out/$(basename "$b")" >/dev/null \
      || { echo "FAIL run: $b ${args[*]}" >&2; exit 1; }
  done
done
for b in "$@"; do
  awk -F, -v name="$(basename "$b")" '
    $3 ~ /cycles/ {c[nc++] = $1} $3 ~ /instructions/ {i[ni++] = $1}
    function med(a, n,   t, j, k) { for (j = 0; j < n; j++) for (k = j + 1; k < n; k++) if (a[k] < a[j]) { t = a[j]; a[j] = a[k]; a[k] = t }; return a[int(n / 2)] }
    END { printf "%-14s cycles %7.1fM  instructions %7.1fM  (n=%d)\n", name, med(c, nc) / 1e6, med(i, ni) / 1e6, nc }
  ' "$out/$(basename "$b")"
done
rm -rf "$out"
