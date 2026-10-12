#!/usr/bin/env bash
# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
# The numbers in the README: best of 5 per case, inside the pixi env (pixi run bench), plus
# CPython's xml.etree.ElementTree (C expat) on the same documents as a baseline.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work
mojo build -I src tools/bench.mojo -o .work/bench
best() { for _ in 1 2 3 4 5; do .work/bench "$@" | awk '{print $NF}'; done | sort -g | head -1 | xargs printf '%.1f'; }
rss() { /usr/bin/time -f %M .work/bench "$@" 2>&1 >/dev/null | tail -1; }
fx=tests/fixtures/arxiv_1706.03762.atom
echo "| case | xmojo ms | peak RSS KB |"
echo "|---|---|---|"
echo "| parse, 80k sibling elements (1.1 MB) | $(best wide 80000) | $(rss wide 80000) |"
echo "| parse, 80k nested elements | $(best deep 80000) | $(rss deep 80000) |"
echo "| parse, arXiv Atom fixture x2000 | $(best file $fx 2000) | |"
echo "| from_xml, 80k items | $(best obj 80000) | $(rss obj 80000) |"
echo "| Records + from_xml per item, 80k | $(best rec 80000) | $(rss rec 80000) |"
echo "| to_xml, 80k items (1.43 MB out) | $(best ser 80000) | $(rss ser 80000) |"
python3 - "$fx" <<'PY'
import sys, time, xml.etree.ElementTree as ET
def best(f, n=5):
    t = []
    for _ in range(n):
        t0 = time.perf_counter(); f(); t.append((time.perf_counter() - t0) * 1e3)
    return min(t)
wide = "<r>" + '<a x="1">t</a>' * 80000 + "</r>"
deep = "<a>" * 80000 + "</a>" * 80000
atom = open(sys.argv[1], encoding="utf-8").read()
print("\nCPython %s ElementTree (expat %s), best of 5:" % (sys.version.split()[0], ".".join(map(str, __import__("pyexpat").version_info))))
print("| parse, 80k sibling elements | %.1f ms |" % best(lambda: ET.fromstring(wide)))
try:
    print("| parse, 80k nested elements | %.1f ms |" % best(lambda: ET.fromstring(deep)))
except Exception as e:
    print("| parse, 80k nested elements | %s |" % type(e).__name__)
print("| parse, arXiv Atom fixture x2000 | %.1f ms |" % best(lambda: [ET.fromstring(atom) for _ in range(2000)]))
PY
