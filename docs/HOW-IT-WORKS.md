# How the flow-powers stack works

Background for anyone using flow-powers. This explains each piece on its own —
what it is, the mechanism that makes it tick, and the commands/skills you'll
touch. For how flow + superpowers combine, see [`DESIGN.md`](DESIGN.md).

The stack has two **core** tools and three **ambient boosters**:

| Piece | Role | Kind |
|---|---|---|
| **flow** | memory + task lifecycle (the OUTER loop) | Go CLI + hooks |
| **superpowers** | disciplined execution (the INNER loop) | CC plugin (skills) |
| **context-mode** | keeps large tool output out of the conversation | CC plugin (MCP + hooks) |
| **LSP parsers** | real code intelligence for edits + verification | CC plugins (native LSP) |
| **Playwright MCP** | agent browser control — the frontend verification arm | MCP server (npx) |

flow + superpowers are the flywheel; context-mode, the LSP parsers, and the
Playwright MCP are best-effort amplifiers the loop assumes are present (it still
runs without them, just noisier, blinder, and unable to *see* UI changes). The
installer wires all five.

---

## flow — cross-session memory + task manager

**Repo:** https://github.com/Facets-cloud/flow · **What it is:** a small Go CLI
(`flow`, on `$PATH`) that tracks your work *and* injects that context into every
Claude session automatically. The pitch: every Claude session normally starts as
"a new hire" with no memory; flow makes session #50 feel like it already knows
your codebase, team, and half-finished threads.

### The model
- **Projects** group related tasks (name, slug, work_dir, priority, status, a
  `brief.md`).
- **Tasks** are units of work (slug, work_dir, priority, status, optional
  project, `waiting_on`, a `brief.md`, and a Claude `session_id` once bound).
- **Playbooks** are reusable runnable definitions; each invocation is a
  reproducible **playbook-run** (a task with its own snapshotted brief).
- **Owners** are durable self-prompting controllers that take ongoing
  responsibility for an outcome ("keep repo X green") and tick on a schedule,
  each tick a fresh headless session.
- **Status** is 3 values: `backlog` → `in-progress` → `done` (plus `archive`).
  Waiting on something? Set `waiting_on`, don't invent a blocked state.

### Where things live
- Metadata (projects, tasks, session ids): SQLite at `~/.flow/flow.db` — you
  never edit this directly.
- **Briefs**: `~/.flow/tasks/<slug>/brief.md` (what/why/where/done-when).
- **Progress notes**: dated markdown under `~/.flow/tasks/<slug>/updates/`.
- **KB** (durable facts): `~/.flow/kb/{user,org,products,processes,business}.md`.
- Authoritative paths are whatever `flow show task <slug>` prints — read those,
  don't reconstruct them.

### The mechanism that matters
1. **`flow do <ref>`** bootstraps/binds a Claude session to a task. `--here`
   binds *this* session (no new tab); `--auto` runs it headlessly in the
   background; `--with "<instr>"` seeds an opening instruction. Binding is what
   flips a task to `in-progress` — you can't set that status by hand.
2. On bind, flow **auto-injects** the brief + KB + project context into the
   session (via SessionStart / UserPromptSubmit hooks it installs). That's the
   "warm start" — the session already knows the background.
3. **`flow done <ref>`** closes the task and runs a **close-out sweep**: it
   re-reads the whole session transcript and writes durable facts (decisions,
   conventions, what got approved) into the KB. This is the compounding step —
   what one session learned is available to all future ones. (Requires a prior
   `flow do` bind, since the sweep needs a transcript to read.)

### Commands you'll actually use
```
flow add task "<name>" --slug <s> --work-dir <path> --mkdir
flow do --here <slug>          # bind this session (mandatory to start work)
flow show task <slug>          # authoritative paths + status
flow done <slug>               # close + KB sweep
flow archive <slug>            # set aside permanently
flow list tasks [--status ...] [--include-archived]
```
Notes and KB are **files you write** (`updates/*.md`, `kb/*.md`) — there is no
`flow note` or `flow kb` subcommand. For usage, run `flow` or `flow <cmd>` bare
(don't pass `--help` to `add`, or it creates a task named "help").

---

## superpowers — a dev methodology for coding agents

**Repo:** https://github.com/obra/superpowers · **What it is:** a Claude Code
plugin — a set of composable **skills** plus instructions that make the agent
*use* them automatically. Instead of jumping straight to code, the agent steps
back, teases out a spec, plans, then executes with discipline. Skills trigger on
their own; you don't invoke them by hand.

### How it triggers
A **SessionStart hook** injects the `using-superpowers` skill at the top of every
session — an instruction so forceful it says *if there's even a 1% chance a skill
applies, you must use it.* That's what makes the methodology automatic rather
than opt-in.

### The skill chain (the core flow)
1. **`brainstorming`** — doesn't write code; interrogates what you're *really*
   trying to do, then shows the spec back in digestible chunks for sign-off.
2. **`writing-plans`** — turns the signed-off spec into an implementation plan
   written for "an enthusiastic junior with no context": bite-sized `- [ ]`
   steps, true red/green TDD, YAGNI, DRY, frequent commits. Saved to
   `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` (respects a user
   plan-location preference). A task is right-sized as *the smallest unit that
   carries its own test cycle and is worth a fresh reviewer's gate.*
3. **`subagent-driven-development`** — dispatches subagents per task, inspects
   and reviews their work, and continues; can run autonomously for a long stretch
   without drifting from the plan. (Without subagents, **`executing-plans`** does
   the same load → review → execute → checkpoint loop single-threaded.)
4. **`finishing-a-development-branch`** — verifies tests, then presents
   merge/PR/cleanup options and executes your choice.

### Supporting skills
- **`test-driven-development`** — real red before green.
- **`verification-before-completion`** — evidence (run the command, show output)
  before claiming anything is done.
- **`requesting-code-review`** / **`receiving-code-review`** — review gates.
- **`systematic-debugging`** — for bugs: reproduce with a failing test → fix →
  verify. (No brainstorm/plan — the failing test is the spec.)
- **`using-git-worktrees`** — isolate parallel work in separate worktrees.
- **`dispatching-parallel-agents`** — fan out independent work.

### Install
```
/plugin install superpowers@claude-plugins-official
```
Works best on a platform with subagents (Claude Code qualifies).

---

---

## context-mode — context hygiene (keep raw bytes out of the conversation)

**Repo:** https://github.com/mksglu/context-mode · **What it is:** a Claude Code
plugin (an MCP server + a skill + hooks) that lets the agent do work in a
sandbox and surface only the *derived answer*, so the raw bytes never enter the
conversation. Every byte a tool returns normally costs context for the rest of
the session; context-mode is the "think in code, don't read raw data into the
window" discipline made into tooling.

### The mechanism that matters
- **`ctx_batch_execute`** — run shell commands in parallel, auto-index each
  output, and (with queries) return matching sections in the *same* round trip.
  The primary research tool: gather + search without a second call.
- **`ctx_execute` / `ctx_execute_file`** — run code (JS/shell/python) over data
  to filter, count, parse, aggregate. Only what you `console.log()` reaches the
  conversation; the source data stays in the sandbox.
- **`ctx_search`** — full-text search over everything indexed (your captures +
  auto-captured session memory). `sort: "timeline"` recovers prior decisions,
  errors, and plans — **it survives `/clear` and compaction**, so a resumed or
  compacted session can recover what it was doing.
- **`ctx_fetch_and_index`** — fetch a URL and index it; page bytes never hit the
  conversation, results are searchable.

### Why it matters for flow-powers
A gated superpowers build emits a *lot* of output — test runs, greps, logs, file
dumps. Routed through `ctx_*`, that output is indexed instead of pasted, so a
long build gets further before hitting the session ceiling — directly
reinforcing the park-and-resume story (see `DESIGN.md` → Session-limit
mitigation). Writes still use the native Write/Edit tools; context-mode is for
gathering and processing, not persisting files.

### Install
```
/plugin marketplace add mksglu/context-mode
/plugin install context-mode@context-mode
```

---

## LSP parsers — real code intelligence for the build

**Repo:** https://github.com/Piebald-AI/claude-code-lsps · **What it is:** a
marketplace of thin, per-language Claude Code plugins that plug real Language
Server Protocol servers into Claude Code's **native LSP support**. Enabled, they
give the agent go-to-definition, find-references, hover types, and diagnostics —
so superpowers edits against real symbol knowledge and catches type/reference
errors immediately, not at test time.

### How it works — two parts, both required
1. **The plugin** ships a `.lsp.json` declaring *how* to launch a server —
   e.g. gopls: `{"go": {"command": "gopls", "transport": "stdio",
   "extensionToLanguage": {".go": "go"}}}`. Enabling the plugin tells Claude
   Code that this server exists.
2. **The server binary** (`gopls`, `pyright-langserver`, `vtsls`, `jdtls`, …)
   must be **installed separately and on the PATH Claude Code inherits.** The
   plugin only declares the launch command; it does not bundle the server.

When both are present and Claude Code is **restarted**, CC spawns the server and
surfaces its output as **diagnostics and navigation — NOT as callable `mcp__`
tools.** So "no new tools appeared" is expected, not a failure.

### The resume trap (why this stack ships a doctor)
Plugin enabled but the binary missing or not on PATH → the LSP **silently does
nothing.** This is the classic "worked in one session, dead after resume"
confusion — often just a PATH issue (e.g. `go install gopls` drops the binary in
`~/go/bin`, which must be on PATH). `hooks/lsp-doctor` checks every enabled LSP's
server binary and prints fix commands; the `session-start` hook folds a warning
into context when one is missing, so the failure surfaces instead of hiding.

### Install
```
/plugin marketplace add Piebald-AI/claude-code-lsps
/plugin install pyright@claude-code-lsps          # + vtsls / jdtls / gopls / …
# then install the server binary, e.g.:
go install golang.org/x/tools/gopls@latest        # ensure ~/go/bin is on PATH
npm i -g pyright @vtsls/language-server typescript
```

---

## Playwright MCP — the frontend verification arm

**Repo:** https://github.com/microsoft/playwright-mcp · **What it is:** an MCP
server (`@playwright/mcp`, run via `npx`) that gives the agent **browser
control** — a set of `mcp__playwright__browser_*` tools to navigate, click,
type, fill forms, snapshot the accessibility tree, and screenshot a running app.

### What it is — and isn't
It is **agent browser control**, *not* a test runner. It does not run your
`*.spec.ts` suite or replace `@playwright/test`; it lets the agent open the app
and *look*. That distinction is the point: for a UI change, "unit tests pass" is
not evidence the thing renders and behaves — a human (or agent) has to see it.
The MCP is how the agent sees it.

### The mechanism that matters
- **`browser_navigate`** to the dev server's URL, then drive the actual change:
  `browser_click`, `browser_type`, `browser_fill_form`, `browser_select_option`.
- **`browser_snapshot`** returns the accessibility tree with stable element refs
  — better than a screenshot for *acting* on the page (it's what you target).
- **`browser_take_screenshot`** captures the rendered result — the concrete
  artifact the verification gate points at. (Saves to the server's cwd root.)
- **`browser_console_messages` / `browser_network_requests`** surface JS errors
  and failed requests — often the real reason a change "looks broken."

### Why it matters for flow-powers
It's the **frontend arm of `verification-before-completion`** (see the loop,
step 2). When a task touches rendered UI, the gate isn't satisfied by unit tests
alone — the agent drives the running app through the MCP and attaches a
snapshot/screenshot as evidence. No browser evidence → the FE change isn't done.

### Install
```
claude mcp add playwright --scope user -- npx -y @playwright/mcp@latest
```
User scope makes it available in every repo. Browsers are fetched on first use
(or `npx playwright install chromium`). Restart Claude Code to load its tools.

---

## One line each
- **flow** decides *what/why* and **remembers** — its `flow done` sweep grows a
  KB that auto-injects into future sessions.
- **superpowers** decides *how* and **executes with discipline** — but forgets
  everything at session end.
- **context-mode** keeps the session **lean** — large tool output is indexed and
  searched, not pasted, so long builds run further.
- **LSP parsers** make edits and verification **sighted** — real defs, refs, and
  diagnostics instead of guessing.
- **Playwright MCP** makes frontend verification **real** — the agent drives the
  running app in a browser instead of assuming the UI works.

flow-powers chains flow + superpowers so memory feeds discipline and discipline
feeds memory; context-mode, the LSP parsers, and the Playwright MCP keep that
loop lean, sighted, and able to verify UI in a real browser. See
[`DESIGN.md`](DESIGN.md).
