#!/bin/bash
# Copy traces recorded in Diagnostics → Traces into Tests/Traces, where the test suite replays them.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$HOME/Library/Application Support/UDockTouch/Traces"
mkdir -p Tests/Traces
cp -n "$SRC"/*.json Tests/Traces/ 2>/dev/null || true
ls Tests/Traces/*.json 2>/dev/null | wc -l | xargs echo "Traces in Tests/Traces:"
