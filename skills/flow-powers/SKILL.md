---
name: flow-powers
description: |
  Runs one build as a compounding loop: flow supplies memory + task lifecycle
  (the OUTER loop), superpowers supplies disciplined execution (the INNER loop).
  Use when starting or resuming real implementation work in a repo — a feature,
  a non-trivial bug, a migration — especially anything worth remembering across
  sessions. Triggers: "build", "implement", "let's start on", "work on this",
  "pick up where I left off", "resume the plan". flow binds + remembers;
  superpowers does the engineering; every close grows the KB so the next build
  starts smarter.
---

# flow-powers

Two tools, each doing only what it is best at. Don't blur them.

- **superpowers owns the HOW, end to end.** Its skills (`brainstorming` →
  `writing-plans` → `subagent-driven-development` → `finishing-a-development-branch`)
  already are the methodology — TDD, YAGNI, subagent review, verification. **Do
  not re-invent its phases or micromanage its chain.** Let it run.
- **flow owns the WHAT/WHY and the memory.** Which task, why it matters, status
  across days, and — the point — a KB that `flow done` grows from each finished
  build and auto-injects into every future session.

**Announce at start:** "Running the flow-powers loop — flow for memory,
superpowers for the build."

## The flywheel (why this beats either tool alone)

```
   flow KB (auto-injected)  ──►  superpowers brainstorm starts warm, not cold
            ▲                                   │
            │                                   ▼
   flow done sweeps the           superpowers plans → builds (gated,
   transcript into the KB   ◄──   subagent-reviewed) → finishes
```

superpowers alone forgets everything at session end. flow alone has no opinion
on execution. Chained, each disciplined build permanently upgrades the
"team-member": the KB gets richer, so the next brainstorm is sharper. That
compounding is the whole product — not any single pass.

## The one rule (prevents drift)

The **plan doc** (`docs/superpowers/plans/…md`, git-tracked with the code) is
canonical for **HOW**. The **flow brief** is canonical for **WHY + status** and
*links* to the plan. Never duplicate one into the other.

---

## The loop

### 1. Bind & load — flow (MANDATORY, first)
Binding is the spine, not a convenience. flow **refuses `in-progress` without a
bound session**, and **`flow done` refuses to close without one** (its KB sweep
reads the transcript). No bind → no lifecycle, no memory.
- Already bound? Good. Otherwise: new work → flow intake to create the task,
  then **`flow do --here <slug>`** (binding is what flips it to `in-progress` —
  never set status by hand; `flow update -status in-progress` is rejected
  without a session). Resuming → `flow do <slug>`.
- The bind auto-injects the brief + KB. **That is your warm start — read it, do
  not cold-start.** If the brief links a plan with unchecked `- [ ]` steps, hand
  superpowers the plan and resume mid-execution.

### 2. Build — superpowers (let it drive)
Hand control to superpowers and stay out of its way. **Which chain it runs
depends on the task shape** — don't force a plan onto a one-line fix:
- **Feature / new work →** `brainstorming` the spec (now seeded by the injected
  KB — a real head start), then `writing-plans`, then
  `subagent-driven-development` (or `executing-plans` without subagents), then
  `finishing-a-development-branch`. Save the plan to
  `docs/superpowers/plans/YYYY-MM-DD-<feature>.md` (repo, git-tracked;
  superpowers respects this user plan-location preference).
- **Bug / regression →** `systematic-debugging` (reproduce with a failing test
  first → fix → verify). No brainstorm, no plan doc — the failing test *is* the
  spec. Finish via `finishing-a-development-branch`.
- Either way, its gate stays its gate: tests pass + review clean +
  `verification-before-completion`. Don't add ceremony it already enforces.

### 3. Mark the trail — flow seams (non-invasive, during step 2)
Two lightweight **file writes** (not CLI — there is no `flow note`/`flow kb`).
Get paths from `flow show task <slug>`; don't reconstruct them.
- **After the plan exists:** add `**Plan:** docs/superpowers/plans/…md` to the
  brief, and write `~/.flow/tasks/<slug>/updates/YYYY-MM-DD-plan-written.md`.
- **As superpowers clears each task/phase gate:** append
  `~/.flow/tasks/<slug>/updates/YYYY-MM-DD-<phase>.md` — one line
  (*"<phase> ✅ tests green, review clean — <what shipped>"*). These + the plan's
  `- [ ]` checkboxes are what let a parked task resume cleanly, mitigating
  superpowers' ~15-20 min session ceiling. Park freely.

### 4. Close & compound — flow (turn the flywheel)
After `finishing-a-development-branch` merges/PRs the work:
- `flow done <slug>` — sweeps the session transcript into the KB (decisions,
  conventions, what review approved). **Requires the step-1 bind**; if the task
  was never truly worked, `flow archive <slug>` instead.
- The sweep is automatic "lessons forward" — no manual step. If something is
  durable but the sweep might miss it, edit the relevant `~/.flow/kb/*.md`
  (`user`/`org`/`products`/`processes`/`business`) yourself. KB is **global, not
  task-scoped** — durable facts only, never ephemeral progress (that's `updates/`).

---

## Amplifiers (use flow's deeper features when they fit)
- **Recurring build shape → flow playbook.** If this kind of build repeats (same
  spec skeleton, same gates), save it as a `flow add playbook` so future runs
  replay the disciplined recipe as a fresh `flow run playbook` session.
- **Ongoing upkeep → flow owner.** For "keep repo X green" style outcomes, a flow
  owner can tick autonomously and run a superpowers debug/fix cycle each tick.
- **High-stakes escalation (optional).** Add extra reviewers (opencode / GLM via
  litellm) through superpowers' `requesting-code-review`. Not a mandatory gate —
  superpowers already reviews.

## Guardrails
- Don't micromanage superpowers' phases — it owns the HOW. flow touches only the
  edges (bind, trail, close).
- Don't duplicate the plan into the brief, or status into the plan.
- Notes/KB are files you Write, not commands. Don't run `flow add task --help`
  (it creates a task named "help"); for usage run `flow` or `flow <cmd>` bare.
- Evidence before "done" — show test + review output.
- Blocked? Set the flow task `waiting_on` and stop; don't guess.
- CLAUDE.md / direct user instructions override this skill.
