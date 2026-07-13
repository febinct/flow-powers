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

## The one rule (prevents drift)

The **plan doc** (`docs/superpowers/plans/…md`, git-tracked with the code) is
canonical for **HOW**. The **flow brief** is canonical for **WHY + status** and
*links* to the plan. Never duplicate one into the other.

## Learn more

- [`HOW-IT-WORKS.md`](HOW-IT-WORKS.md) — how **flow** and **superpowers** each
  work on their own (model, mechanism, commands/skills). Start here if either
  tool is new to you.
- [`DESIGN.md`](DESIGN.md) — the full seam-by-seam integration design.

## Install

```bash
# prerequisites (installed, not vendored):
#   flow >= v0.1.0-alpha.24 on PATH  — https://github.com/Facets-cloud/flow (flow init)
#     (earlier builds lack `do --auto`/`--with` + owners; verify with `flow do -h`)
#   superpowers plugin  — /plugin install superpowers@claude-plugins-official

git clone --recurse-submodules <this-repo> && cd flow-powers
./install.sh          # symlinks the skill, registers the SessionStart hook
```

Then start a new Claude Code session (or `/clear`). The hook injects a pointer;
the `flow-powers` skill triggers when you start real build work.

## Layout

```
flow-powers/
├── skills/flow-powers/SKILL.md   the orchestration protocol (the heart)
├── hooks/hooks.json              SessionStart registration
├── hooks/session-start           injects the flow-powers pointer
├── .claude-plugin/plugin.json    Claude Code plugin manifest
├── install.sh                    idempotent installer (backs up settings.json)
├── HOW-IT-WORKS.md               how flow & superpowers each work (background)
├── DESIGN.md                     mental model + seams + tradeoffs
└── vendor/                       pinned submodules (reference only)
    ├── flow/          @ v0.1.0-alpha.24
    └── superpowers/   @ v6.1.1
```

`vendor/` is pinned reference so the glue matches real upstream behaviour; the
runtime uses your **installed** flow + superpowers. Update reference with
`git submodule update --remote`.
