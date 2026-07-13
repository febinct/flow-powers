# How flow and superpowers work

Background for anyone using flow-powers. This explains each tool on its own —
what it is, the mechanism that makes it tick, and the commands/skills you'll
touch. For how they combine, see [`DESIGN.md`](DESIGN.md).

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

## One line each
- **flow** decides *what/why* and **remembers** — its `flow done` sweep grows a
  KB that auto-injects into future sessions.
- **superpowers** decides *how* and **executes with discipline** — but forgets
  everything at session end.

flow-powers chains them so the memory feeds the discipline and the discipline
feeds the memory. See [`DESIGN.md`](DESIGN.md).
