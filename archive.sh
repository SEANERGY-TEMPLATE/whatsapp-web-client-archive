#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

# cron runs with a bare PATH, which misses an nvm-installed node. Pick the
# highest installed version rather than hardcoding one, so a node upgrade does
# not silently break the scheduled run.
if ! command -v node >/dev/null 2>&1; then
    nvm_bin="$(find "$HOME/.nvm/versions/node" -maxdepth 2 -type d -name bin \
        2>/dev/null | sort -V | tail -1)"
    [ -n "$nvm_bin" ] && export PATH="$nvm_bin:$PATH"
fi

if ! command -v node >/dev/null 2>&1; then
    echo "archive.sh: node not found on PATH" >&2
    exit 127
fi

# Keep one previous generation so the log cannot grow without bound.
LOG=archive.log
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 1048576 ]; then
    mv -f "$LOG" "$LOG.1"
fi

echo "=== run started $(date '+%Y-%m-%d %H:%M:%S %Z') ==="

if [ ! -d node_modules ]; then
    npm install --no-audit --no-fund
fi

set +e
./archive-version
rc=$?
set -e

echo "=== run finished rc=$rc $(date '+%Y-%m-%d %H:%M:%S %Z') ==="
exit $rc
