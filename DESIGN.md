# flow-powers — integration design

Combine **[flow](https://github.com/Facets-cloud/flow)** (cross-session memory +
task manager) with **[superpowers](https://github.com/obra/superpowers)**
(in-session dev methodology) into one workflow — the best of each, no forking.

## The core idea: a compounding flywheel, not a pipeline

Neither tool is missing a *step*. They're missing each other's *nature*:

- **superpowers** is a disciplined but **amnesiac** executor. It brainstorms →
  plans → builds (subagent-reviewed, TDD, verified) → finishes, at a quality one
  session can't match by hand — then forgets all of it at session end.
- **flow** is **memory + judgment**. It decides what/why, tracks status across
  days, and — the killer feature — `flow done` **sweeps the finished session's
  transcript into a KB that auto-injects into every future session.**

Chain them and the output is a flywheel:

```
   flow KB (auto-injected)  ──►  superpowers brainstorm starts WARM
            ▲                                   │
            │                                   ▼
   flow done sweeps the           plan → subagent-reviewed gated build
   transcript into the KB   ◄──   → finish
```

Each disciplined build permanently upgrades the "team-member": the KB gets
richer, so the next brainstorm is sharper. **That compounding is the product** —
not any single linear pass. Design decisions below all serve keeping the
flywheel turning.

## Division of labor (don't blur the two)

| Concern | Owner | Lives at |
|---|---|---|
| *What / why* + status + cross-session memory | **flow** | `~/.flow/tasks/<slug>/brief.md`, `updates/`, `~/.flow/kb/*.md` |
| *How* — spec, plan, execution, verification | **superpowers** | its skill chain + `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` (repo, git-tracked) |

**superpowers owns the HOW end to end.** Its skills already are the methodology;
flow-powers does **not** re-invent or micromanage its phases. flow touches only
the *edges* — bind at the start, mark the trail at gates, close at the end.

The one rule against drift: **plan doc = canonical for HOW**; **flow brief =
canonical for WHY + status** and links to the plan. Never duplicate either into
the other.

## The seams (where flow touches superpowers — only the edges)

| # | Seam | What happens | Mechanism |
|---|---|---|---|
| 1 | **Bind & load** | `flow do --here <task>` binds the session and auto-injects brief + KB → superpowers `brainstorming` starts warm | CLI (mandatory) |
| 2 | **Plan artifact** | `writing-plans` → `docs/superpowers/plans/…md`; brief gets a `**Plan:** …` link | file write |
| 3 | **Gate trail** | as superpowers clears each task/phase gate → append `updates/YYYY-MM-DD-<phase>.md` (one line) | file write |
| 4 | **Close & compound** | `finishing-a-development-branch` → `flow done` sweeps transcript into KB → next brainstorm is smarter | CLI |

> **Verified by dogfooding.** flow gates the whole task lifecycle on `flow do`:
> a task can't go `in-progress` and can't be `flow done`-closed without a bound
> session. **Seam 1 binding is the spine, not a convenience.** Notes and KB are
> **file writes** — there is no `flow note` or `flow kb` subcommand.

## Why the work-atom already lines up

- superpowers task right-sizing: *"the smallest unit that carries its own test
  cycle and is worth a fresh reviewer's gate."*
- flow task/update model: a unit of work with its own brief + progress notes.

Both define the same atom. flow-powers just makes superpowers' gate (tests +
review) leave a flow trail — no reconciliation needed. And the plan's `- [ ]`
checkboxes double as flow's resumable phase state.

## Amplifiers (flow features worth reaching for)

- **Playbooks** — when a build *shape* recurs, save it as a flow playbook; each
  run replays the disciplined superpowers recipe as a fresh, reproducible
  session. Turns a one-off good build into a repeatable one.
- **Owners** — for standing outcomes ("keep repo X green"), a flow owner ticks
  autonomously and can run a superpowers debug/fix cycle each tick.
- **Lessons are automatic.** "Carry lessons forward" is not a manual step — the
  `flow done` sweep does it. Only hand-edit `kb/*.md` for a durable fact the
  sweep might miss. KB is **global, not task-scoped** — durable facts only.

## What this is NOT

- Not a fork or a merged binary. Both stay as pinned submodules under `vendor/`
  for reference; the runtime targets the **installed** `flow` + superpowers.
- Not a re-implementation of either. It's a thin orchestrator that binds flow's
  memory to superpowers' discipline at four edges — and otherwise gets out of
  the way.

## Session-limit mitigation

superpowers' subagent-heavy verification can burn a session in ~15–20 min. The
mitigation is structural: every gate writes a flow note and the plan encodes
state as `- [ ]` checkboxes, so a fresh `flow do <task>` resumes mid-plan
cleanly. Park-and-resume is a feature, not a failure — and it's exactly what
flow was built for.
