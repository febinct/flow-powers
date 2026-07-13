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

# --- 0. reference submodules (best-effort; NOT required at runtime) -----------
# vendor/ is pinned reference only — the tool runs against the installed flow
# binary + superpowers plugin. If cloned without --recurse-submodules, init them
# so the reference is present, but never fail the install over it.
if [ -f "$REPO/.gitmodules" ] && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [ -z "$(ls -A "$REPO/vendor/flow" 2>/dev/null)" ] || [ -z "$(ls -A "$REPO/vendor/superpowers" 2>/dev/null)" ]; then
    echo "  .. submodules missing — fetching reference (git submodule update --init)"
    git -C "$REPO" submodule update --init --recursive 2>&1 | sed 's/^/     /' \
      || echo "  ! note: submodule fetch failed — reference-only, install continues"
  fi
fi

# --- 1. skill (symlink so repo edits propagate) ------------------------------
mkdir -p "$SKILLS_DIR"
ln -sfn "$REPO/skills/flow-powers" "$SKILLS_DIR/flow-powers"
echo "  ok: skill -> $SKILLS_DIR/flow-powers"

# --- 2. hook scripts executable ---------------------------------------------
chmod +x "$REPO/hooks/session-start" "$REPO/hooks/lsp-doctor"

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

# --- 4. productivity stack: context-mode + LSP parser plugins ----------------
# Best-effort. flow-powers runs without these, but they sharpen the loop:
# context-mode keeps large tool output out of the conversation; the LSP servers
# give superpowers real code intelligence (defs, refs, diagnostics) mid-build.
# Override the LSP set with FLOW_POWERS_LSPS="pyright gopls" (etc); "" to skip.
if command -v claude >/dev/null 2>&1; then
  mkts="$(claude plugin marketplace list 2>/dev/null || true)"
  add_mkt() {  # name  github-source
    if printf '%s' "$mkts" | grep -qE "❯ ${1}([[:space:]]|$)"; then
      echo "  ok: marketplace $1 present"
    else
      claude plugin marketplace add "$2" >/dev/null 2>&1 \
        && echo "  ok: marketplace $1 added ($2)" \
        || echo "  ! note: could not add marketplace $1 — add manually: /plugin marketplace add $2"
    fi
  }
  add_mkt context-mode     mksglu/context-mode
  add_mkt claude-code-lsps Piebald-AI/claude-code-lsps

  installed="$(claude plugin list 2>/dev/null || true)"
  want=( "context-mode@context-mode" )
  for l in ${FLOW_POWERS_LSPS-pyright vtsls jdtls gopls}; do want+=( "$l@claude-code-lsps" ); done
  for p in "${want[@]}"; do
    if printf '%s' "$installed" | grep -qE "❯ ${p}([[:space:]]|$)"; then
      echo "  ok: plugin $p present"
    else
      claude plugin install "$p" >/dev/null 2>&1 \
        && echo "  ok: plugin $p installed" \
        || echo "  ! note: could not install $p — install manually: /plugin install $p"
    fi
  done
else
  echo "  ! warning: 'claude' CLI not on PATH — skipping plugin install. Add manually:"
  echo "      /plugin marketplace add mksglu/context-mode"
  echo "      /plugin marketplace add Piebald-AI/claude-code-lsps"
  echo "      /plugin install context-mode@context-mode  (+ pyright/vtsls/jdtls/gopls@claude-code-lsps)"
fi

# --- 5. LSP language-server binaries -----------------------------------------
# Plugins declare HOW to launch a server; the binary must be on the PATH Claude
# Code inherits. Auto-install gopls (the common miss: `go install` drops it in
# ~/go/bin, which must be on PATH), then report the whole picture.
if command -v go >/dev/null 2>&1 \
   && ! command -v gopls >/dev/null 2>&1 \
   && [ ! -x "$(go env GOPATH 2>/dev/null)/bin/gopls" ]; then
  echo "  .. installing gopls (go install)"
  go install golang.org/x/tools/gopls@latest >/dev/null 2>&1 \
    && echo "  ok: gopls -> $(go env GOPATH)/bin/gopls  (ensure that dir is on PATH)" \
    || echo "  ! note: gopls install failed — run: go install golang.org/x/tools/gopls@latest"
fi
echo "  -- LSP server binary check --"
"$REPO/hooks/lsp-doctor" || true

echo "flow-powers: done. RESTART Claude Code (not --resume) to load the skill,"
echo "             hook, and any newly-enabled plugins + language servers."
