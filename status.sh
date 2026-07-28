#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

if ! command -v node >/dev/null 2>&1; then
    nvm_bin="$(find "$HOME/.nvm/versions/node" -maxdepth 2 -type d -name bin \
        2>/dev/null | sort -V | tail -1)"
    [ -n "$nvm_bin" ] && export PATH="$nvm_bin:$PATH"
fi

echo "Archived versions: $(find . -maxdepth 1 -name '*.html' | wc -l)"
echo "Newest archived:   $(cat .version 2>/dev/null || echo '(none)')"
echo

# Exits non-zero if the most recent run failed, so this doubles as a check.
node -e '
const fs = require("fs");

let lines;
try {
    lines = fs.readFileSync("archive-log.jsonl", "utf-8").trim().split("\n").filter(Boolean);
} catch {
    console.log("No run recorded yet (archive-log.jsonl is missing).");
    process.exit(0);
}
if (!lines.length) {
    console.log("No run recorded yet (archive-log.jsonl is empty).");
    process.exit(0);
}

const entries = lines.map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);

console.log("Last 10 runs (oldest first):");
for (const e of entries.slice(-10)) {
    const parts = [e.ts, e.ok ? "OK  " : "FAIL", e.version ? `${e.action} ${e.version}` : e.action];
    if (e.bundleSimilarity !== undefined) {
        parts.push(`vs ${e.comparedWith}: ${(e.bundleSimilarity * 100).toFixed(1)}% similar, risk ${e.risk}`);
    }
    if (e.diverged) parts.push("DIVERGED");
    if (e.error) parts.push(`— ${e.error}`);
    console.log("  " + parts.join("  "));
}

const diverged = entries.filter((e) => e.diverged);
if (diverged.length) {
    console.log(`\n${diverged.length} archived build(s) diverged 30%+ from their predecessor:`);
    for (const e of diverged) {
        console.log(`  ${e.version} vs ${e.comparedWith} — ${(e.bundleSimilarity * 100).toFixed(1)}% similar (risk ${e.risk})`);
    }
    console.log("Run ./compare-versions --verbose to see which bundles moved.");
}

const last = entries[entries.length - 1];
if (!last.ok) {
    console.log("\nMost recent run FAILED — see archive.log for the full trace.");
    process.exit(1);
}
console.log("\nMost recent run succeeded.");
'
