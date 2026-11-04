#!/usr/bin/env bash
# CI entry: the full offline gate, then the precompiled package.
set -euo pipefail
cd "$(dirname "$0")/.."
pixi run gate
pixi run build
