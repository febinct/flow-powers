# flow-powers

A **compounding flywheel** from two tools, each doing only what it's best at:

- **[flow](https://github.com/Facets-cloud/flow)** — memory + judgment. What to
  work on, why, status across days, and a KB that `flow done` grows from each
  finished build and auto-injects into every future session.
- **[superpowers](https://github.com/obra/superpowers)** — disciplined but
  amnesiac execution. brainstorm → plan → subagent-reviewed gated build →
  finish, then forgets it all at session end.

Neither lacks a *step* — they lack each other's *nature*. Chained, superpowers'
quality output feeds flow's memory, and flow's memory makes superpowers' next
brainstorm smarter. That compounding is the point.

```
   flow KB (auto-injected)  ──►  superpowers brainstorm starts WARM
            ▲                                   │
            │                                   ▼
   flow done sweeps the           plan → subagent-reviewed gated build
   transcript into the KB   ◄──   → finish
```

superpowers owns the **HOW** end to end — flow-powers does not micromanage its
phases. flow touches only the **edges**:

```
1  Bind & load   flow do --here <task>   MANDATORY — binds session, flips status,
                 enables the KB sweep; brief + KB auto-inject as a warm start
2  Build         hand off to superpowers: brainstorming → writing-plans
                 (→ docs/superpowers/plans/*.md) → subagent-driven-development
                 → finishing-a-development-branch.  Let it drive.
3  Mark trail    link plan in brief.md; append updates/…-phase-N.md at each gate
4  Close         flow done <task>  → transcript swept into KB → next build smarter
```

> Notes and KB are **markdown files you write** (`updates/*.md`, `kb/*.md`) —
> `flow note` / `flow kb` are not commands. The task lifecycle is gated on
> `flow do`: no bind → can't go in-progress, can't `flow done`. Lessons carry
> forward automatically via the sweep — no manual step. Recurring build shapes →
> save a **flow playbook** to replay the recipe.

## Ambient stack (best-effort amplifiers the installer wires in)

Three capabilities the loop assumes are present — it runs without them, just
noisier, blinder, and unable to *see* UI changes:

- **[context-mode](https://github.com/mksglu/context-mode)** — routes large tool
  output (test runs, logs, greps) through a sandbox so raw bytes stay out of the
  conversation. Keeps long gated builds from drowning the context window.
- **[LSP parsers](https://github.com/Piebald-AI/claude-code-lsps)**
  (pyright / vtsls / jdtls / gopls / …) — real code intelligence (defs, refs,
  diagnostics) for superpowers' edits and its verification gate. They surface as
  diagnostics, **not** as tools, and need the server binary on PATH + a restart.
- **[Playwright MCP](https://github.com/microsoft/playwright-mcp)** — agent
  browser control (`mcp__playwright__browser_*`). The **frontend arm** of the
  verification gate: for UI changes, the agent drives the running app —
  navigate, click, snapshot, screenshot — so "it renders and behaves" is
  evidenced, not assumed. It's browser control, **not** a test runner. Installed
  at user scope; skip via `FLOW_POWERS_PLAYWRIGHT=0`.

## The one rule (prevents drift)

The **plan doc** (`docs/superpowers/plans/…md`, git-tracked with the code) is
canonical for **HOW**. The **flow brief** is canonical for **WHY + status** and
*links* to the plan. Never duplicate one into the other.

## Learn more

- [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) — how **flow**, **superpowers**,
  **context-mode**, and the **LSP parsers** each work on their own (model,
  mechanism, commands/skills). Start here if any piece is new to you.
- [`docs/DESIGN.md`](docs/DESIGN.md) — the full seam-by-seam integration design.

## Install

**Prerequisites** (installed, not vendored):
- `flow` >= v0.1.0-alpha.24 on PATH — https://github.com/Facets-cloud/flow (run `flow init`).
  Earlier builds lack `do --auto`/`--with` + owners; verify with `flow do -h`.
- superpowers plugin — `/plugin install superpowers@claude-plugins-official`

### Option A — marketplace (quick: skill + hook only)

```
/plugin marketplace add https://github.com/febinct/flow-powers.git
/plugin install flow-powers@flow-powers
```

Gets you the `flow-powers` skill and its SessionStart hook. You still need the
prerequisites above, and this path does **not** wire the ambient stack
(context-mode + LSP parsers) — for that, use Option B.

> Use the full **HTTPS URL** (not the `febinct/flow-powers` shorthand) — the
> shorthand resolves to SSH (`git@github.com:…`), which fails without SSH keys;
> the `.git` HTTPS URL clones over HTTPS and works for any public installer.

### Option B — installer (full: skill + hook + ambient stack)

```bash
git clone --recurse-submodules https://github.com/febinct/flow-powers && cd flow-powers
./install.sh          # symlinks the skill + registers the SessionStart hook,
                      # then installs the ambient stack and checks LSP binaries
```

`install.sh` also (best-effort) adds the context-mode + claude-code-lsps
marketplaces, installs context-mode plus an LSP set (override with
`FLOW_POWERS_LSPS="pyright gopls"`, or `""` to skip), adds the **Playwright MCP**
at user scope (skip with `FLOW_POWERS_PLAYWRIGHT=0`), auto-installs `gopls` when
Go is present, and runs `hooks/lsp-doctor` to flag any LSP server binary missing
from PATH. It degrades gracefully to printed instructions if the `claude` CLI
isn't found.

Then **restart Claude Code** (a full relaunch, not `--resume`) so the hook,
skill, and any newly-enabled plugins + language servers + MCP servers load. The
hook injects a pointer; the `flow-powers` skill triggers when you start real
build work.

## Layout

```
flow-powers/
├── skills/                       one dir per skill (each with a SKILL.md)
│   └── flow-powers/SKILL.md      the orchestration protocol (the heart)
├── hooks/hooks.json              SessionStart registration
├── hooks/session-start           injects the flow-powers pointer (+ LSP warning)
├── hooks/lsp-doctor              checks each enabled LSP's server binary is on PATH
├── .claude-plugin/plugin.json    Claude Code plugin manifest
├── .claude-plugin/marketplace.json  makes the repo /plugin-installable
├── install.sh                    idempotent installer (skill, hook, stack, backups)
├── docs/
│   ├── HOW-IT-WORKS.md           how flow, superpowers, context-mode, LSPs & Playwright each work
│   └── DESIGN.md                 mental model + seams + tradeoffs
├── blog.md                       the story: why chain these, what compounds
└── vendor/                       pinned submodules (reference only)
    ├── flow/               @ v0.1.0-alpha.24
    ├── superpowers/        @ v6.1.1
    ├── context-mode/       @ v1.0.169+
    ├── claude-code-lsps/   @ main
    └── playwright-mcp/     @ v0.0.78
```

`vendor/` is pinned reference so the glue matches real upstream behaviour; the
runtime uses your **installed** flow + superpowers. Update reference with
`git submodule update --remote`.

### Adding a skill

The repo hosts multiple skills. To add one:

1. Create `skills/<name>/SKILL.md` (with `name` + `description` frontmatter).
2. List it in `.claude-plugin/plugin.json` →
   `"skills": ["./skills/flow-powers", "./skills/<name>"]`.

That's it — `install.sh` symlinks **every** `skills/*/SKILL.md` automatically (no
installer edit), and marketplace installs read the `plugin.json` array. Hooks are
shared at the plugin level, so a new skill doesn't need its own hook.
