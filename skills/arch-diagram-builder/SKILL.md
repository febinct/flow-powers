---
name: arch-diagram-builder
description: |
  Turn a plain-English description of a system or process into a polished,
  self-contained HTML diagram — architecture, workflow, sequence, data-flow, or
  state/lifecycle — with deterministic auto-layout, a dark/light theme toggle,
  and one-click export to PNG/JPEG/WebP (up to 4×) and dual-theme SVG. Zero
  runtime dependencies; the output is one shareable HTML file. Use when the user
  asks for an architecture diagram, system/infra/cloud diagram, technical
  workflow, approval flow, CI/CD or runbook diagram, API/request sequence
  diagram, data pipeline / ETL / data-flow map, or a state machine / lifecycle
  diagram, or says "diagram this", "draw the architecture", "visualize this
  flow", "make a diagram".
---

# Arch Diagram Builder

Describe a system or process as a small **JSON IR**; a deterministic engine
computes the layout (no hand-placed coordinates), validates it, and renders a
**self-contained, themeable HTML file** with export built in. Requires `node`
(≥18) on PATH; zero npm dependencies.

**Announce at start:** "Using the arch-diagram-builder skill (JSON IR → engine)."

## The workflow

1. **Understand the system/flow** from the user's description — nodes (services,
   steps, actors, states, stores) and edges (calls, transitions, messages). Ask
   if the structure is ambiguous; don't invent architecture.
2. **Write the IR** to a `.json` file (shape below).
3. **Validate** (catches bad refs, overlaps, edge-crossings with actionable hints):
   ```bash
   node scripts/diagram.mjs validate diagram.json
   ```
4. **Render** to a self-contained HTML file:
   ```bash
   node scripts/diagram.mjs render diagram.json --out <name>.html [--animate]
   ```
5. **Report the path** and tell the user: open it, press **T** theme, **E**
   export (Copy PNG / PNG·JPEG·WebP up to 4× / dual-theme SVG), **A** animate.
6. **Iterate** by editing the IR and re-rendering.

If `validate`/`render` prints ⚠ warnings (overlap, edge crosses a node), fix the
IR — reorder nodes, or set explicit `row`/`col` (architecture/dataflow/lifecycle)
or `lane`/`phase` (workflow) — then re-render until clean. Use `--strict` to make
warnings fail the build.

## The IR

```json
{
  "type": "architecture | dataflow | lifecycle | workflow | sequence",
  "title": "Short title",
  "animate": false,
  "nodes": [
    { "id": "svc", "label": "Order Service", "cat": "backend",
      "row": 0, "col": 2,            // optional grid (architecture/dataflow/lifecycle)
      "lane": "Manager", "phase": "Review" }   // workflow only
  ],
  "edges": [
    { "from": "gw", "to": "svc", "label": "HTTPS", "kind": "normal" }
  ],
  "lanes": ["Employee", "Manager", "Finance"],   // workflow (optional; else derived)
  "phases": ["Submit", "Review", "Settle"],       // workflow (optional; else derived)
  "actors": ["client", "api", "db"]               // sequence order (optional; else node order)
}
```

- **`cat`** (semantic tech category → consistent color): `frontend`, `backend`,
  `database`, `cloud`, `security`, `queue`, `external`. Map a component's tech to
  the closest one (`redis`→`queue`, `aws.lambda`→`backend`, `postgres`→`database`,
  `openai`→`external`, auth/PII→`security`). Omit for a neutral node.
- **`kind`** (edge): `normal`, `async` (dashed), `exception` (red dashed),
  `happy` (accent, emphasized, animatable).
- **Layout is automatic.** You usually give only `nodes` + `edges`; the engine
  ranks and places them. Add `row`/`col` only to override. Workflow needs
  `lane`+`phase` per node (multiple nodes per cell stack automatically).

## Types → layout
- **architecture / dataflow / lifecycle** — layered: nodes ranked left→right by
  dependency (or explicit grid); orthogonal edge routing through column gaps.
- **workflow** — swimlanes (`lane`) × phases (`phase`) with lane bands + phase
  headers; happy path emphasized, exceptions red.
- **sequence** — actor columns with vertical lifelines; edges are ordered
  messages drawn top→down.

## CLI (`scripts/diagram.mjs`)
| Command | Does |
|---|---|
| `render <ir> --out <html> [--animate] [--strict]` | validate → layout → self-contained HTML |
| `validate <ir> [--strict]` | schema + layout report (overlaps, crossings) with hints |
| `inspect <ir>` | print the computed layout JSON (coordinates) — for debugging |
| `examples --out-dir <dir>` | write one example IR per type (see `scripts/examples/`) |
| `demo [--out <html>]` | render a bundled example |
| `doctor` | environment + self-test render |

Start from `scripts/examples/<type>.json` when unsure of the shape; the formal
contract is `scripts/schemas/diagram.schema.json`.

## Escape hatch — hand-authored SVG
For a bespoke layout the engine doesn't produce, author the SVG body yourself
(using the semantic classes `.node`/`.cat-*`/`.label`/`.edge`/`.edge-label`,
never hard-coded colors) and wrap it:
```bash
node scripts/build-diagram.mjs --title "…" --svg diagram.svg --out out.html
```

## Guardrails
- **Prefer the IR + engine** — deterministic layout beats hand-placed coordinates.
- **Fix warnings before finishing** — overlaps/crossings mean the IR needs
  reordering or explicit placement; don't ship a diagram with layout warnings.
- **Never hard-code colors** (escape hatch) — use `cat`/semantic classes so the
  theme toggle and dual-theme SVG export work.
- **Don't invent architecture** — diagram what the user described; ask when a
  relationship is unclear.
