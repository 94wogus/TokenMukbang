#!/usr/bin/env bash
#
# AX visual-verification GATE (Claude Code Stop hook).
#
# When the agent tries to finish a turn while it has uncommitted UI changes
# (App/**) whose renders are stale, this builds + renders the snapshots and
# BLOCKS the turn once, telling the agent to Read the PNGs before declaring
# done. The gate clears itself: after a render, .snapshots/ is newer than the
# sources, so the next Stop passes — no infinite loop, no manual step.
#
# Wired from .claude/settings.json (Stop hook). Output contract: print
# {"decision":"block","reason":"…"} on stdout to block; exit 0 silently to pass.
set -euo pipefail

input="$(cat)"

# Already inside a stop-hook block → don't re-block (belt-and-suspenders; the
# staleness check below already prevents loops once a render exists).
if printf '%s' "$input" | grep -q '"stop_hook_active":[[:space:]]*true'; then
  exit 0
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"

# Only the UI layer matters for a visual gate. No uncommitted App/ change → pass.
changed="$(git status --porcelain -- App 2>/dev/null || true)"
[ -n "$changed" ] || exit 0

# Stale if there are no renders yet, or any App/*.swift is newer than the newest PNG.
newest_png="$(ls -t .snapshots/*.png 2>/dev/null | head -1 || true)"
if [ -n "$newest_png" ] && [ -z "$(find App -name '*.swift' -newer "$newest_png" -print -quit 2>/dev/null)" ]; then
  exit 0   # renders are up to date
fi

log="$(mktemp -t tmk-snapshot-hook)"
if ! tools/snapshot.sh >"$log" 2>&1; then
  reason="Visual-verify gate: tools/snapshot.sh FAILED — the UI build is broken. See $log (tail: $(tail -3 "$log" | tr '\n' ' ')). Fix the build before finishing."
  printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$reason" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
  exit 0
fi

reason="Visual-verify gate: you changed UI (App/**). Fresh renders are in .snapshots/ — Read the relevant PNGs (e.g. .snapshots/live-tab-dashboard.png and .snapshots/live-themelight-charcoal.png) and confirm the change looks right before declaring done. This gate clears automatically once renders are current."
printf '{"decision":"block","reason":%s}\n' "$(printf '%s' "$reason" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')"
exit 0
