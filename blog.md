# How I got my local Claude Code setup to stop forgetting everything

Every Claude Code session starts like a brilliant new hire with amnesia.

Sharp reasoning, zero memory. It doesn't remember yesterday's decision, the
convention we agreed on, or the half-finished thread I left open. So every
morning I'd re-explain my own codebase to it. And left alone, it sprints
straight to code instead of thinking first.

I got tired of that. My local working setup has come together over the last
year, all around one idea: **a build should make the next build smarter, not
start from zero.**

Here's where it's landed.

## The core: memory + discipline, chained

Two open-source tools, each doing one thing well:

- **flow** — memory. A tiny CLI that tracks work as tasks, binds a Claude
  session to one, and — the part that matters — when I close a task it sweeps the
  whole transcript into a knowledge base that auto-injects into every future
  session.
- **superpowers** — discipline. It forces a real methodology: brainstorm the
  spec, write a plan, build test-first with review, verify before claiming done.
  Great output. Then it forgets everything at session end.

Neither is missing a *step*. They're missing each other's *nature*. So I chained
them into one loop I call **flow-powers**: flow's memory feeds superpowers'
discipline, and each disciplined build feeds flow's memory back. The knowledge
base gets richer, so the next brainstorm starts warm instead of cold. That
compounding is the whole point.

## The stack around it

A loop is only as good as what it can see and hold, so I wired in three more:

- **context-mode** — keeps huge tool output (test runs, logs, greps) out of the
  conversation, so long sessions don't drown in their own noise.
- **LSP servers** (gopls, pyright, vtsls, jdtls) — real go-to-definition and
  diagnostics, so edits are made with actual code knowledge, not guesses.
- **Playwright MCP** — lets the agent open the running app in a browser and
  *look* at a UI change instead of assuming it works.

One installer sets all of it up.

## Then I started building my own skills

Once the loop worked, adding capabilities got addictive:

- **duckdb-analysis** — point it at a CSV / Parquet / Excel file and it runs SQL
  in-process, returning only the answer. The raw rows never touch the context
  window.
- **arch-diagram-builder** — describe a system in plain English, get a
  self-contained HTML architecture diagram with a dark/light toggle and one-click
  export. It has a real layout engine and validation, not just an LLM guessing
  coordinates. The fun part: I had it draw *its own repo's* architecture, and
  those diagrams now live in the README.

## The honest lessons (this is the real post)

Building it taught me more than using it:

**Silent failures cost the most.** My SessionStart hook — the thing that's
supposed to load the whole system — was quietly doing nothing for a while. It
branched on the wrong environment variable, so Claude Code just ignored its
output. No error. A hook that "runs fine" and a hook whose output is actually
*used* are two different claims. Test the second one.

**"It broke" is usually "it was never wired."** Resume looked broken in Go repos
— turned out `gopls` had installed to a directory that wasn't on the PATH Claude
Code inherits. The tool was declared, the binary just wasn't reachable. Now a
doctor script surfaces that instead of letting it hide.

**The compounding only works if you actually close things.** The entire payoff
lives in the "close the task" sweep. Half-finished tasks that never close teach
the system nothing. The machinery isn't the habit — closing the loop is.

## Would I recommend it?

If you do multi-session work worth remembering *and* you'll actually close your
tasks — yes, it changes how the tool feels by session #50. If you mostly do
quick one-offs, a good `CLAUDE.md` gets you most of the way with none of the
overhead. Be honest about which one you are.

It's all open source and tested in CI. Happy to share the repo if it's useful to
anyone building out their own agent setup.

*#ClaudeCode #AI #DeveloperTools #Engineering #LLM #Productivity*
