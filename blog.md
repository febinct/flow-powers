# flow-powers: giving a coding agent both a memory and a spine

Every Claude Code session starts as a brilliant new hire with amnesia. It can
reason about your code, but it doesn't remember yesterday — not the decision you
made, not the convention you agreed on, not the half-finished thread you left
open. And left to its own devices, it tends to sprint straight to code instead
of thinking first.

Two different problems. It turns out two existing tools each solve one of them —
and chaining them produces something neither has alone.

## Two tools, two natures

**[flow](https://github.com/Facets-cloud/flow)** is memory. A small Go CLI that
tracks your work as tasks with briefs and progress notes, binds a Claude session
to a task, and — the part that matters — when you close a task with `flow done`,
it sweeps the whole session transcript and distills durable facts into a
knowledge base that **auto-injects into every future session.** Session #50
starts already knowing your codebase, your team, your conventions.

**[superpowers](https://github.com/obra/superpowers)** is discipline. A Claude
Code plugin that forces the agent through a real methodology — brainstorm the
spec, write a plan, build it test-first with subagent review, verify before
claiming done. The output quality is higher than one-shot prompting. But it
forgets everything at session end.

Neither is missing a *step*. They're missing each other's *nature*. superpowers
is a disciplined amnesiac; flow is memory with no opinion on execution.

## The flywheel

Chain them and you get a loop that compounds:

```
   flow KB (auto-injected)  ──►  superpowers brainstorm starts WARM
            ▲                                   │
            │                                   ▼
   flow done sweeps the           plan → subagent-reviewed gated build
   transcript into the KB   ◄──   → finish
```

Every disciplined build permanently upgrades the "team member." The KB gets
richer, so the next brainstorm is sharper, so the next build is better, so the
KB it produces is richer still. That compounding — not any single pass — is the
product.

flow-powers is deliberately thin. superpowers owns the **HOW** end to end;
flow-powers never micromanages its phases. flow touches only four edges:

1. **Bind** the session to a task (`flow do --here`) — warm start, brief + KB injected.
2. **Build** — hand off to superpowers and get out of the way.
3. **Trail** — drop a one-line progress note at each phase gate.
4. **Close** (`flow done`) — sweep the transcript into the KB. Next build starts smarter.

One rule keeps it honest: the plan doc is canonical for *how*, the flow brief is
canonical for *why + status*. Never duplicate one into the other.

## Making the loop lean and sighted

Two ambient boosters make the loop practical, not just elegant:

- **[context-mode](https://github.com/mksglu/context-mode)** keeps the session
  *lean*. A gated build emits a firehose of output — test runs, greps, logs. Left
  raw, that output eats the context window and cuts the session short. context-mode
  runs the work in a sandbox and returns only the derived answer, so a long build
  gets further before hitting the ceiling. It even indexes session memory that
  survives `/clear`, so a resumed session can recover what it was doing.
- **LSP parsers** ([claude-code-lsps](https://github.com/Piebald-AI/claude-code-lsps))
  make edits *sighted*. Real Language Server Protocol servers — gopls, pyright,
  vtsls, jdtls — give the agent go-to-definition, references, and diagnostics, so
  superpowers edits against real symbol knowledge and catches type errors
  immediately instead of at test time.
- **[Playwright MCP](https://github.com/microsoft/playwright-mcp)** makes
  frontend verification *real*. For a UI change, passing unit tests proves
  nothing about whether the thing renders. The MCP is agent browser control — not
  a test runner — so the agent drives the running app (navigate, click, snapshot,
  screenshot) and the verification gate points at an actual rendered result.
  Without it, "the UI works" is an assumption; with it, it's evidence.

## The honest caveat

The flywheel only turns if you **close tasks.** The entire compounding benefit
lives in the `flow done` sweep. If tasks pile up `in-progress` for weeks and
never close, the sweep never runs, the KB never grows, and you're paying the
ceremony cost with none of the payoff. This is the failure mode to watch for in
yourself: having the machinery is not the same as turning the flywheel.

And it isn't free. Two external dependencies, a plan-and-gate rhythm that's
overkill for a one-line fix, and overlap with Claude Code's now-native plan mode,
todos, and memory. flow-powers earns its keep when you do multi-session work
worth remembering *and* you actually close the loop. For quick one-offs, plain
Claude Code plus a good `CLAUDE.md` gets you most of the way with none of the
overhead.

## Two lessons from building the stack

**Silent failures are the expensive ones.** The SessionStart hook that injects
the flow-powers pointer was, for a while, doing nothing under Claude Code. It
branched on `CLAUDE_PLUGIN_ROOT` to pick its output format — a variable Claude
Code sets only for *plugin* hooks. flow-powers installs a *user-settings* hook,
where that variable is unset, so it emitted the SDK-standard shape that Claude
Code ignores. No error, no warning — the context just evaporated. The fix was to
key on `CLAUDECODE` instead. Lesson: a hook that "runs fine" and a hook whose
output is actually *consumed* are different claims. Test the second one.

**Declaring a capability isn't having it.** An LSP plugin only declares *how* to
launch a server; the server binary must be installed separately and on PATH. Miss
that — `gopls` installed to `~/go/bin`, which wasn't on the PATH Claude Code
inherited — and the LSP silently does nothing. It *looks* like "resume broke."
That's why the stack ships `hooks/lsp-doctor`: it checks every enabled LSP's
binary and, when one is missing, the session-start hook surfaces a warning
instead of letting the failure hide. Make the invisible failure visible.

## Try it

```bash
git clone --recurse-submodules <this-repo> && cd flow-powers
./install.sh
```

Then restart Claude Code, start real build work, and — the part that matters —
close your tasks. See [`README.md`](README.md) for setup and
[`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) for how each piece works.
