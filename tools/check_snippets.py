#!/usr/bin/env python3
# Copyright 2026 amarbaro.org. Licensed under the Apache License, Version 2.0.
"""Every ```mojo block with a `def main` in README.md, AGENTS.md and skills/**/*.md must compile
and run against src/. Blocks are written to .work/snippets/ (a directory with no packages, so
nothing shadows -I src). Run inside the pixi env; exits non-zero with FAIL k/N."""
import pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / ".work/snippets"
OUT.mkdir(parents=True, exist_ok=True)
for old in OUT.glob("*.mojo"):
    old.unlink()
docs = [ROOT / "README.md", ROOT / "AGENTS.md"] + sorted((ROOT / "skills").rglob("*.md"))
blocks = []
for doc in docs:
    if doc.exists():
        for k, code in enumerate(re.findall(r"```mojo\n(.*?)```", doc.read_text(), re.S)):
            if "def main" in code:
                blocks.append(("%s_%d" % (doc.relative_to(ROOT).as_posix().replace("/", "_"), k), code))
bad = []
for name, code in blocks:
    f = OUT / (name + ".mojo")
    f.write_text(code)
    try:
        r = subprocess.run(["mojo", "run", "-I", str(ROOT / "src"), str(f)], capture_output=True, text=True, timeout=300)
        ok = r.returncode == 0
    except subprocess.TimeoutExpired:
        ok, r = False, None
    if not ok:
        bad.append(name)
        print("FAIL %s: %s" % (name, "timeout" if r is None else r.stderr.strip().splitlines()[-1:]))
if bad or not blocks:
    print("FAIL %d/%d snippets: %s" % (len(bad), len(blocks), " ".join(bad) or "none found"))
    sys.exit(1)
print("snippets OK %d/%d" % (len(blocks), len(blocks)))
