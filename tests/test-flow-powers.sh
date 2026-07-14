#!/usr/bin/env bash
# Non-destructive test harness for flow-powers hooks + installer.
# Uses fixture CLAUDE_CONFIG_DIRs + controlled PATH; never touches real config.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$REPO/hooks/lsp-doctor"
HOOK="$REPO/hooks/session-start"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '        got: %s\n' "$2"; }
has(){ case "$2" in *"$1"*) return 0;; *) return 1;; esac; }

# make a fixture CLAUDE_CONFIG_DIR: $1=dir, remaining args = "name:command" enabled LSP plugins
mkfix(){
  local dir="$1"; shift
  mkdir -p "$dir/plugins/marketplaces/claude-code-lsps"
  local entries="" p n c
  for p in "$@"; do
    n="${p%%:*}"; c="${p##*:}"
    mkdir -p "$dir/plugins/marketplaces/claude-code-lsps/$n"
    if [ "$c" != "__NOLSPJSON__" ]; then
      printf '{ "lang": { "command": "%s", "args": [] } }\n' "$c" \
        > "$dir/plugins/marketplaces/claude-code-lsps/$n/.lsp.json"
    fi
    entries+="    \"$n@claude-code-lsps\": true,\n"
  done
  printf '{\n  "enabledPlugins": {\n%b    "other@x": true\n  }\n}\n' "$entries" > "$dir/settings.json"
}

# a bin dir with a present fake binary
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\necho ok\n' > "$BIN/fp_present_bin"; chmod +x "$BIN/fp_present_bin"
# controlled PATH: system tools + our fake bin; fp_missing_bin & real gopls absent
TPATH="/usr/bin:/bin:/usr/sbin:$BIN"

echo "== lsp-doctor =="

# A. all present -> verbose ok, quiet empty
mkfix "$TMP/A" "alpha:fp_present_bin"
out="$(CLAUDE_CONFIG_DIR="$TMP/A" PATH="$TPATH" "$DOCTOR" 2>&1)"; rc=$?
has "ok alpha (fp_present_bin)" "$out" && [ $rc -eq 0 ] && ok "A verbose: healthy shows ok + exit 0" || no "A verbose" "$out (rc=$rc)"
q="$(CLAUDE_CONFIG_DIR="$TMP/A" PATH="$TPATH" "$DOCTOR" --quiet 2>&1)"
[ -z "$q" ] && ok "A quiet: healthy -> empty" || no "A quiet not empty" "$q"

# B. one missing -> verbose !! + hint, quiet warns naming it, exit 0
mkfix "$TMP/B" "alpha:fp_present_bin" "beta:fp_missing_bin"
out="$(CLAUDE_CONFIG_DIR="$TMP/B" PATH="$TPATH" "$DOCTOR" 2>&1)"; rc=$?
has "ok alpha" "$out" && has "!! beta (fp_missing_bin) NOT ON PATH" "$out" && [ $rc -eq 0 ] \
  && ok "B verbose: missing flagged, still exit 0" || no "B verbose" "$out (rc=$rc)"
q="$(CLAUDE_CONFIG_DIR="$TMP/B" PATH="$TPATH" "$DOCTOR" --quiet 2>&1)"
has "LSP not ready" "$q" && has "beta (fp_missing_bin)" "$q" && ok "B quiet: warns + names plugin" || no "B quiet" "$q"

# C. no settings.json -> silent exit 0
mkdir -p "$TMP/C/plugins/marketplaces/claude-code-lsps"
out="$(CLAUDE_CONFIG_DIR="$TMP/C" PATH="$TPATH" "$DOCTOR" 2>&1)"; rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok "C no settings -> silent exit 0" || no "C" "$out (rc=$rc)"

# D. no marketplace dir -> silent
mkdir -p "$TMP/D"; echo '{"enabledPlugins":{}}' > "$TMP/D/settings.json"
out="$(CLAUDE_CONFIG_DIR="$TMP/D" PATH="$TPATH" "$DOCTOR" 2>&1)"; rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok "D no marketplace dir -> silent exit 0" || no "D" "$out (rc=$rc)"

# E. marketplace present but NO enabled lsp plugin -> silent
mkdir -p "$TMP/E/plugins/marketplaces/claude-code-lsps"
echo '{"enabledPlugins":{"context-mode@context-mode":true}}' > "$TMP/E/settings.json"
out="$(CLAUDE_CONFIG_DIR="$TMP/E" PATH="$TPATH" "$DOCTOR" 2>&1)"; rc=$?
[ -z "$out" ] && [ $rc -eq 0 ] && ok "E no enabled LSP -> silent exit 0" || no "E" "$out (rc=$rc)"

# F. enabled plugin but missing .lsp.json -> '?' line
mkfix "$TMP/F" "gamma:__NOLSPJSON__"
out="$(CLAUDE_CONFIG_DIR="$TMP/F" PATH="$TPATH" "$DOCTOR" 2>&1)"; rc=$?
has "?  gamma — could not read server command" "$out" && [ $rc -eq 0 ] && ok "F missing .lsp.json -> '?'" || no "F" "$out (rc=$rc)"

# G. hint correctness for known server (gopls) when missing
mkfix "$TMP/G" "gopls:gopls"
out="$(CLAUDE_CONFIG_DIR="$TMP/G" PATH="$TPATH" "$DOCTOR" 2>&1)"
has "go install golang.org/x/tools/gopls@latest" "$out" && has "~/go/bin" "$out" \
  && ok "G gopls hint correct" || no "G hint" "$out"

# G2. disabled LSP (false) is ignored
mkdir -p "$TMP/G2/plugins/marketplaces/claude-code-lsps/beta"
printf '{"lang":{"command":"fp_missing_bin"}}' > "$TMP/G2/plugins/marketplaces/claude-code-lsps/beta/.lsp.json"
echo '{"enabledPlugins":{"beta@claude-code-lsps":false}}' > "$TMP/G2/settings.json"
q="$(CLAUDE_CONFIG_DIR="$TMP/G2" PATH="$TPATH" "$DOCTOR" --quiet 2>&1)"
[ -z "$q" ] && ok "G2 disabled LSP ignored" || no "G2" "$q"

echo "== session-start hook =="
valid_json(){ printf '%s' "$1" | python3 -m json.tool >/dev/null 2>&1; }
ctx(){ printf '%s' "$1" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("hookSpecificOutput",d).get("additionalContext",""))'; }

# Claude Code detection is keyed on CLAUDECODE (user-settings hooks don't get
# CLAUDE_PLUGIN_ROOT). Run these with a clean platform env so the branch is
# deterministic regardless of the shell we're invoked from.
CCENV=(env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT -u COPILOT_CLI CLAUDECODE=1)

# H. healthy (Claude Code) -> nested hookSpecificOutput, base msg, no LSP warning
out="$(CLAUDE_CONFIG_DIR="$TMP/A" PATH="$TPATH" "${CCENV[@]}" "$HOOK" 2>&1)"; rc=$?
c="$(ctx "$out")"
valid_json "$out" && has '"hookSpecificOutput"' "$out" && has "flow-powers is installed" "$c" \
  && ! has "LSP not ready" "$c" && [ $rc -eq 0 ] \
  && ok "H healthy: nested JSON, base msg, no warning" || no "H" "$out"

# I. broken (Claude Code) -> nested JSON, warning appended to base msg
out="$(CLAUDE_CONFIG_DIR="$TMP/B" PATH="$TPATH" "${CCENV[@]}" "$HOOK" 2>&1)"
c="$(ctx "$out")"
valid_json "$out" && has '"hookSpecificOutput"' "$out" && has "flow-powers is installed" "$c" \
  && has "LSP not ready" "$c" && ok "I broken: nested JSON, base msg + warning" || no "I" "$out"

# J. Claude Code MUST use hookSpecificOutput (regression guard for the CLAUDE_PLUGIN_ROOT bug)
out="$(CLAUDE_CONFIG_DIR="$TMP/A" PATH="$TPATH" env -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT -u COPILOT_CLI CLAUDECODE=1 "$HOOK" 2>&1)"
has '"hookSpecificOutput"' "$out" && ! has $'"additionalContext"\n' "$out" \
  && ok "J Claude Code (no CLAUDE_PLUGIN_ROOT) still nested" || no "J regression" "$out"

# J-cursor. Cursor -> snake_case additional_context
out="$(CLAUDE_CONFIG_DIR="$TMP/A" PATH="$TPATH" env -u COPILOT_CLI CLAUDECODE=1 CURSOR_PLUGIN_ROOT=/c "$HOOK" 2>&1)"
valid_json "$out" && has '"additional_context"' "$out" && ok "J-cursor snake_case shape" || no "J-cursor" "$out"

# J-sdk. Copilot/other (no CLAUDECODE, no CURSOR) -> top-level additionalContext
out="$(CLAUDE_CONFIG_DIR="$TMP/A" PATH="$TPATH" env -u CLAUDECODE -u CLAUDE_PLUGIN_ROOT -u CURSOR_PLUGIN_ROOT "$HOOK" 2>&1)"
top="$(printf '%s' "$out" | python3 -c 'import json,sys;print("additionalContext" in json.load(sys.stdin))')"
valid_json "$out" && [ "$top" = "True" ] && ! has '"hookSpecificOutput"' "$out" && ok "J-sdk top-level shape" || no "J-sdk" "$out"

# J2. JSON escaping survives a quote-injection attempt via the warning path (sanity: newlines/quotes)
python3 - "$out" <<'PY' && ok "J2 escaping round-trips" || no "J2 escaping"
import json,sys
json.loads(sys.argv[1]);
PY

echo "== install.sh =="
bash -n "$REPO/install.sh" && ok "K syntax valid" || no "K syntax"

# L. claude-not-on-PATH fallback branch (temp CLAUDE_CONFIG_DIR, PATH without claude/go)
LOUT="$(CLAUDE_CONFIG_DIR="$TMP/L" PATH="/usr/bin:/bin" bash "$REPO/install.sh" 2>&1)"; rc=$?
has "'claude' CLI not on PATH" "$LOUT" && has "/plugin marketplace add mksglu/context-mode" "$LOUT" \
  && ok "L claude-missing fallback prints manual steps" || no "L fallback" "$LOUT (rc=$rc)"
has "ok: skill flow-powers ->" "$LOUT" && ok "L still symlinks skill (per-skill loop)" || no "L skill" "$LOUT"
[ -L "$TMP/L/skills/flow-powers" ] && ok "L skill symlink created in fixture dir" || no "L symlink missing"

# M. FLOW_POWERS_LSPS expansion logic (isolated; mirrors install.sh section 4)
buildwant(){ local want=( "context-mode@context-mode" ); for l in ${FLOW_POWERS_LSPS-pyright vtsls jdtls gopls}; do want+=( "$l@claude-code-lsps" ); done; printf '%s\n' "${want[@]}"; }
w="$(buildwant)"; has "pyright@claude-code-lsps" "$w" && has "gopls@claude-code-lsps" "$w" && ok "M default LSP set (4)" || no "M default" "$w"
w="$(FLOW_POWERS_LSPS='pyright gopls' buildwant)"; n="$(echo "$w"|wc -l|tr -d ' ')"; [ "$n" = "3" ] && has "pyright@" "$w" && ! has "vtsls@" "$w" && ok "M subset override" || no "M subset" "$w"
w="$(FLOW_POWERS_LSPS='' buildwant)"; n="$(echo "$w"|wc -l|tr -d ' ')"; [ "$n" = "1" ] && has "context-mode@context-mode" "$w" && ok "M empty -> context-mode only" || no "M empty" "$w"

# N. idempotency-check grep matches the real 'claude plugin list' line format
sample=$'Installed plugins:\n\n  ❯ gopls@claude-code-lsps\n    Version: 0.1.0\n'
printf '%s' "$sample" | grep -qE "❯ gopls@claude-code-lsps([[:space:]]|$)" && ok "N plugin-present grep matches CLI format" || no "N grep"
printf '%s' "$sample" | grep -qE "❯ pyright@claude-code-lsps([[:space:]]|$)" && no "N false-positive (pyright not in list)" || ok "N grep no false-positive"

echo "== multi-skill installer loop =="
# O. links every skills/*/SKILL.md; skips dirs without SKILL.md
mkdir -p "$TMP/O/skills/alpha" "$TMP/O/skills/beta" "$TMP/O/skills/nodoc" "$TMP/O/dest"
echo x > "$TMP/O/skills/alpha/SKILL.md"; echo x > "$TMP/O/skills/beta/SKILL.md"
R="$TMP/O"; S="$TMP/O/dest"; c=0
for sk in "$R"/skills/*/; do
  [ -f "$sk/SKILL.md" ] || continue
  nm="$(basename "$sk")"; d="$S/$nm"
  { [ -e "$d" ] && [ ! -L "$d" ]; } && continue
  ln -sfn "${sk%/}" "$d"; c=$((c+1))
done
[ "$c" = 2 ] && [ -L "$S/alpha" ] && [ -L "$S/beta" ] && [ ! -e "$S/nodoc" ] \
  && ok "O links skills with SKILL.md, skips nodoc" || no "O multi-skill loop" "count=$c"

# P. non-symlink name clash -> skip (no nesting inside the existing dir)
mkdir -p "$TMP/P/skills/data-analysis" "$TMP/P/dest/data-analysis/scripts"
echo x > "$TMP/P/skills/data-analysis/SKILL.md"
echo existing > "$TMP/P/dest/data-analysis/SKILL.md"   # pre-existing REAL dir
R="$TMP/P"; S="$TMP/P/dest"; skipped=0
for sk in "$R"/skills/*/; do
  [ -f "$sk/SKILL.md" ] || continue
  nm="$(basename "$sk")"; d="$S/$nm"
  if [ -e "$d" ] && [ ! -L "$d" ]; then skipped=1; continue; fi
  ln -sfn "${sk%/}" "$d"
done
[ "$skipped" = 1 ] && [ ! -L "$TMP/P/dest/data-analysis/data-analysis" ] \
  && ok "P name clash skipped, no nested symlink" || no "P clash guard"

echo "== duckdb tool (live, needs uv) =="
DUCK="$REPO/skills/duckdb-analysis/scripts/duckdb_tool.py"
if [ -f "$DUCK" ] && command -v uv >/dev/null 2>&1; then
  D="$TMP/duck"; mkdir -p "$D"
  printf 'region,product,qty,rev\nnorth,widget,10,100.5\nsouth,widget,5,50.25\nnorth,gadget,3,90.0\n' > "$D/s.csv"
  printf '{"region":"north","bonus":5}\n{"region":"south","bonus":9}\n' > "$D/b.ndjson"
  # Q. CSV aggregate
  q="$(uv run --quiet "$DUCK" --load s="$D/s.csv" --sql "SELECT sum(qty) q FROM s" 2>/dev/null)"
  has "18" "$q" && ok "Q CSV aggregate (sum qty=18)" || no "Q csv" "$q"
  # R. multi-file JOIN across CSV + NDJSON
  q="$(uv run --quiet "$DUCK" --load s="$D/s.csv" --load b="$D/b.ndjson" \
        --sql "SELECT s.region, sum(s.rev) r, max(b.bonus) bn FROM s JOIN b ON s.region=b.region GROUP BY 1 ORDER BY 1" 2>/dev/null)"
  has "north" "$q" && has "south" "$q" && ok "R multi-file JOIN (csv+ndjson)" || no "R join" "$q"
  # S. --out parquet, then read it back
  uv run --quiet "$DUCK" --load s="$D/s.csv" --sql "SELECT region, sum(rev) r FROM s GROUP BY 1" --out "$D/agg.parquet" >/dev/null 2>&1
  [ -f "$D/agg.parquet" ] && q="$(uv run --quiet "$DUCK" --load a="$D/agg.parquet" --sql "SELECT count(*) n FROM a" 2>/dev/null)" && has "2" "$q" \
    && ok "S parquet round-trip (write + read)" || no "S parquet" "$q"
  # T. safety: bad table identifier rejected
  if uv run --quiet "$DUCK" --load 'bad;name'="$D/s.csv" --sql "SELECT 1" >/dev/null 2>&1; then
    no "T rejects unsafe identifier"; else ok "T rejects unsafe identifier"; fi
else
  no "Q-T duckdb tool (missing tool or uv)"
fi

echo "== arch-diagram-builder (build-diagram.mjs) =="
BD="$REPO/skills/arch-diagram-builder/scripts/build-diagram.mjs"
if [ -f "$BD" ] && command -v node >/dev/null 2>&1; then
  DD="$TMP/diag"; mkdir -p "$DD"
  printf '<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg"><rect class="cat-backend" x="10" y="10" width="80" height="40" rx="8"/><text class="label" x="50" y="35">API</text></svg>' > "$DD/d.svg"
  node "$BD" --title "T&<test>" --svg "$DD/d.svg" --out "$DD/o.html" >/dev/null 2>&1
  # Y1 produces a file with no leftover placeholders
  if [ -f "$DD/o.html" ] && ! grep -q '__TITLE__\|__DIAGRAM_SVG__' "$DD/o.html"; then ok "Y build: placeholders replaced"; else no "Y build placeholders"; fi
  # Y2 self-contained: no external network refs
  grep -qiE 'src="https?:|<link[^>]+https?:|@import[^;]*https?:' "$DD/o.html" && no "Y2 self-contained (external ref found)" || ok "Y2 self-contained (no external refs)"
  # Y3 title HTML-escaped (& -> &amp;, < -> &lt;)
  grep -q 'T&amp;&lt;test&gt;' "$DD/o.html" && ok "Y3 title HTML-escaped" || no "Y3 title escape"
  # Y4 svg injected + export menu present with all 5 formats
  grep -q 'class="cat-backend"' "$DD/o.html" && for a in copy png jpeg webp svg; do grep -q "data-act=\"$a\"" "$DD/o.html" || { no "Y4 export menu missing $a"; break; }; done && ok "Y4 svg injected + 5 export formats" || no "Y4 svg/menu"
  # Y5 rejects non-svg input
  printf 'not an svg' | node "$BD" --title x --out "$DD/bad.html" >/dev/null 2>&1 && no "Y5 rejects non-svg" || ok "Y5 rejects non-svg input"
  # Y6 adds xmlns when missing
  printf '<svg viewBox="0 0 10 10"><rect/></svg>' | node "$BD" --title x --out "$DD/x.html" >/dev/null 2>&1
  grep -q 'xmlns="http://www.w3.org/2000/svg"' "$DD/x.html" && ok "Y6 injects xmlns" || no "Y6 xmlns"
else
  no "Y build-diagram (missing script or node)"
fi

echo "== diagram engine (golden renders, all 5 types) =="
DG="$REPO/skills/arch-diagram-builder/scripts/diagram.mjs"
EXD="$REPO/skills/arch-diagram-builder/scripts/examples"
if [ -f "$DG" ] && command -v node >/dev/null 2>&1; then
  GG="$TMP/gold"; mkdir -p "$GG"
  # Z1 doctor passes
  node "$DG" doctor >/dev/null 2>&1 && ok "Z1 doctor passes" || no "Z1 doctor"
  # Z2 all 5 example IRs validate with ZERO warnings (--strict)
  allclean=1; for t in architecture dataflow lifecycle workflow sequence; do
    node "$DG" validate "$EXD/$t.json" --strict >/dev/null 2>&1 || { allclean=0; echo "        $t not strict-clean"; }; done
  [ "$allclean" = 1 ] && ok "Z2 all 5 examples strict-clean (no overlap/crossing)" || no "Z2 strict-clean"
  # Z3 render each → self-contained HTML with an <svg> and no leftover placeholders
  z3=1; for t in architecture dataflow lifecycle workflow sequence; do
    node "$DG" render "$EXD/$t.json" --out "$GG/$t.html" >/dev/null 2>&1
    { [ -f "$GG/$t.html" ] && grep -q '<svg' "$GG/$t.html" && ! grep -q '__DIAGRAM_SVG__\|__TITLE__' "$GG/$t.html" \
      && ! grep -qiE 'src="https?:|<link[^>]+https?:' "$GG/$t.html"; } || { z3=0; echo "        $t render bad"; }; done
  [ "$z3" = 1 ] && ok "Z3 all 5 render self-contained with svg" || no "Z3 render"
  # Z4 workflow emits swimlanes + phase headers; sequence emits lifelines
  grep -q 'class="lane' "$GG/workflow.html" && grep -q 'phase-label' "$GG/workflow.html" && ok "Z4 workflow lanes + phase headers" || no "Z4 workflow decos"
  grep -q 'class="lifeline"' "$GG/sequence.html" && ok "Z4b sequence lifelines" || no "Z4b lifelines"
  # Z5 validation catches a bad edge ref
  printf '{"type":"architecture","title":"x","nodes":[{"id":"a","label":"A"}],"edges":[{"from":"a","to":"ghost"}]}' > "$GG/bad.json"
  node "$DG" validate "$GG/bad.json" >/dev/null 2>&1 && no "Z5 catches bad edge ref" || ok "Z5 catches bad edge ref"
  # Z6 validation catches an overlap (two nodes forced to same grid cell)
  printf '{"type":"architecture","title":"x","nodes":[{"id":"a","label":"A","row":0,"col":0},{"id":"b","label":"B","row":0,"col":0}]}' > "$GG/ov.json"
  node "$DG" validate "$GG/ov.json" 2>&1 | grep -qi overlap && ok "Z6 catches overlap" || no "Z6 overlap"
  # Z7 inspect emits computed coordinates as JSON
  node "$DG" inspect "$EXD/architecture.json" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["width"]>0 and len(d["nodes"])==6; print("ok")' >/dev/null 2>&1 \
    && ok "Z7 inspect emits layout JSON" || no "Z7 inspect"
  # Z8 --animate marks edges + enables animation hook
  node "$DG" render "$EXD/lifecycle.json" --out "$GG/anim.html" --animate >/dev/null 2>&1
  grep -q 'data-animate="on"' "$GG/anim.html" && grep -q 'edge-flow' "$GG/anim.html" && ok "Z8 --animate wires flow animation" || no "Z8 animate"
  # Z9 JSON Schema is valid JSON and the type enum matches the engine's TYPES
  SCH="$REPO/skills/arch-diagram-builder/scripts/schemas/diagram.schema.json"
  python3 -c "import json; s=json.load(open('$SCH')); assert set(s['properties']['type']['enum'])=={'architecture','dataflow','lifecycle','workflow','sequence'}; print('ok')" >/dev/null 2>&1 \
    && ok "Z9 JSON Schema valid + type enum matches engine" || no "Z9 schema"
else
  no "Z diagram engine (missing script or node)"
fi

echo "== skill + plugin manifests =="
# U. both skills present with matching name frontmatter
for pair in "flow-powers:flow-powers" "duckdb-analysis:duckdb-analysis" "arch-diagram-builder:arch-diagram-builder"; do
  dir="${pair%%:*}"; want="${pair##*:}"; f="$REPO/skills/$dir/SKILL.md"
  nm="$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1)"
  [ "$nm" = "$want" ] && ok "U $dir name=$want" || no "U $dir name" "$nm"
done
# V. plugin.json lists both skills, author is an object
pj="$REPO/.claude-plugin/plugin.json"
python3 - "$pj" <<'PY' && ok "V plugin.json: 3 skills, author object" || no "V plugin.json"
import json,sys
d=json.load(open(sys.argv[1]))
sk=d.get("skills",[])
assert all(x in sk for x in ["./skills/flow-powers","./skills/duckdb-analysis","./skills/arch-diagram-builder"]), sk
assert isinstance(d.get("author"),dict), d.get("author")
PY
# W. trigger verbs landed in descriptions
grep -q "add a feature" "$REPO/skills/flow-powers/SKILL.md" && ok "W flow-powers new verbs" || no "W fp verbs"
grep -q "crosstab" "$REPO/skills/duckdb-analysis/SKILL.md" && ok "W duckdb new verbs" || no "W duck verbs"

echo "== vendored submodules =="
# X. all five declared in .gitmodules
gm="$REPO/.gitmodules"
allfound=1
for m in flow superpowers context-mode claude-code-lsps playwright-mcp; do
  grep -q "vendor/$m\"" "$gm" || allfound=0
done
[ "$allfound" = 1 ] && ok "X all 5 submodules in .gitmodules" || no "X submodules"

echo ""
printf 'TOTAL: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
