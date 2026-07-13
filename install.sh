#!/usr/bin/env bash
# flow-powers installer — wires the skill + SessionStart hook into ~/.claude.
# Idempotent. Backs up settings.json before touching it. Targets the INSTALLED
# flow binary + superpowers plugin; this repo only provides the glue.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "flow-powers: repo=$REPO  claude=$CLAUDE_DIR"

# --- preflight ---------------------------------------------------------------
command -v flow >/dev/null 2>&1 || echo "  ! warning: 'flow' not on PATH — install from https://github.com/Facets-cloud/flow"
if ! find "$CLAUDE_DIR/plugins" -maxdepth 3 -iname '*superpower*' 2>/dev/null | grep -q .; then
  echo "  ! warning: superpowers plugin not detected — install via: /plugin install superpowers@claude-plugins-official"
fi

# --- 1. skill (symlink so repo edits propagate) ------------------------------
mkdir -p "$SKILLS_DIR"
ln -sfn "$REPO/skills/flow-powers" "$SKILLS_DIR/flow-powers"
echo "  ok: skill -> $SKILLS_DIR/flow-powers"

# --- 2. hook script executable ----------------------------------------------
chmod +x "$REPO/hooks/session-start"

# --- 3. merge SessionStart hook into settings.json (backup + idempotent) -----
python3 - "$SETTINGS" "$REPO/hooks/session-start" <<'PY'
import json, os, sys, shutil, time
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(settings_path):
    shutil.copy(settings_path, settings_path + ".bak." + time.strftime("%Y%m%d%H%M%S"))
    with open(settings_path) as f:
        data = json.load(f) or {}
hooks = data.setdefault("hooks", {})
starts = hooks.setdefault("SessionStart", [])
cmd = f'"{hook_cmd}"'
exists = any(
    h.get("command") == cmd
    for entry in starts for h in entry.get("hooks", [])
)
if exists:
    print("  ok: hook already registered")
else:
    starts.append({
        "matcher": "startup|clear|compact",
        "hooks": [{"type": "command", "command": cmd, "async": False}],
    })
    os.makedirs(os.path.dirname(settings_path), exist_ok=True)
    with open(settings_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  ok: hook registered in {settings_path}")
PY

echo "flow-powers: done. Start a new session (or /clear) to load the skill + hook."
