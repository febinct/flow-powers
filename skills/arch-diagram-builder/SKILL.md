---
name: arch-diagram-builder
description: |
  Turn a plain-English description of a system or process into a polished,
  self-contained HTML diagram — architecture, workflow, sequence, data-flow, or
  state/lifecycle — with a built-in dark/light theme toggle and one-click export
  to PNG (copy or download) and dual-theme SVG. Zero dependencies; the output is
  one shareable HTML file. Use when the user asks for an architecture diagram,
  system/infra/cloud diagram, technical workflow, approval flow, CI/CD or runbook
  diagram, API/request sequence diagram, data pipeline / ETL / data-flow map, or
  a state machine / lifecycle diagram, or says "diagram this", "draw the
  architecture", "visualize this flow", "make a diagram".
---

# Arch Diagram Builder

Generate a **self-contained, themeable HTML diagram** from a description. The
output is a single file (inline SVG + a tiny theming/export runtime, no external
requests) the user can open, toggle dark/light on, and export as PNG or SVG.

**Announce at start:** "Using the diagram skill — self-contained themeable HTML."

## How it works — you author the SVG, the tool wraps it

`scripts/build-diagram.mjs` (Node, zero deps) injects your SVG into
`scripts/template.html`, which supplies the theme toggle, the export menu, and a
CSS-variable color system. **You never hand-write the chrome** — you write only
the diagram's SVG body, using the template's semantic classes so both themes
stay consistent:

| Class | Use for |
|---|---|
| `.node` | box/container fill + border |
| `.node-accent` | a highlighted/primary node (accent fill) |
| `.label` | text inside a node |
| `.label-accent` | text inside an accent node |
| `.muted` | secondary/caption text |
| `.edge` | connector lines/paths (use with `marker-end` arrowheads) |
| `.edge-label` | text on a connector |

**Semantic tech categories** — colour a node by *what it is* (consistent across
the diagram, themed automatically). Put the category on the `<rect>`; keep
`.label` on the text:

| Class | For components like |
|---|---|
| `.cat-frontend` | web/mobile UI, SPA, CDN, gateway edge |
| `.cat-backend` | services, APIs, workers, functions (`aws.lambda`, app servers) |
| `.cat-database` | `postgres`, MySQL, Mongo, warehouses |
| `.cat-cloud` | cloud/infra/platform (`aws.*`, k8s, `github-actions`) |
| `.cat-security` | auth, IAM, secrets, WAF, PII/trust boundaries |
| `.cat-queue` | `redis`, Kafka, SQS, message buses, caches |
| `.cat-external` | third-party / external systems (`openai`, Stripe) — dashed |

Map a component's tech name to the closest category (e.g. `redis` → `.cat-queue`,
`aws.lambda` → `.cat-backend`). No icon library — category = colour + grouping.

Colors come from CSS variables (`--node`, `--edge`, `--text`, `--accent`, …) that
the template flips between themes — so **never hard-code hex colors** in the SVG;
use the classes (or `fill="var(--…)"`). That is what makes one SVG render right
in both themes and export as a dual-theme (system-following) standalone SVG.

## Workflow

1. **Understand the system/flow.** Identify the nodes (services, steps, actors,
   stores, states) and the edges (calls, data, transitions) from the user's
   description. Ask if the structure is ambiguous — don't invent architecture.
2. **Author the SVG body.** Lay out nodes on a grid; connect with `.edge` paths +
   an arrowhead `<marker>`. Give the `<svg>` an explicit `viewBox` sized to the
   content (this drives export dimensions). Keep it clean and readable; group
   related nodes. Use the semantic classes above.
3. **Build the file:**
   ```bash
   node scripts/build-diagram.mjs --title "<diagram title>" --svg diagram.svg --out <name>.html
   # or pipe the SVG on stdin:  … | node scripts/build-diagram.mjs --title "…" --out <name>.html
   ```
4. **Report the path** and tell the user: open it, press **T** to toggle theme,
   **E** to export. Export menu: Copy PNG to clipboard, download PNG / JPEG /
   WebP (rasterized natively at **up to 4×** — auto-stepped down for very large
   diagrams to stay under the canvas limit), or a dual-theme **SVG** that follows
   the reader's system theme (ideal for GitHub READMEs).
5. **Iterate by request** — "add Redis", "move auth left", "use the accent for
   the gateway": edit the SVG body and rebuild.

## Diagram types (same tool, different layout)
- **Architecture / infra** — boxes for services/stores, edges for calls; group by tier.
- **Workflow / process** — steps left→right or top→down; decision diamonds; approval/CI-CD/runbook flows.
- **Sequence** — actor columns with vertical lifelines; horizontal `.edge` messages top→down.
- **Data-flow / pipeline** — sources → transforms → sinks; label edges with what flows; mark trust/PII boundaries with a dashed container.
- **State / lifecycle** — states as nodes, transitions as labeled edges; mark start/end.

## Guardrails
- **Never hard-code colors** — use the semantic classes / CSS vars, or the theme
  toggle and dual-theme SVG export break.
- **Always set a `viewBox`** on the `<svg>` — export sizing depends on it.
- **Self-contained only** — no external fonts, scripts, or images in the SVG; the
  whole value is a single shareable file.
- **Don't invent architecture** — diagram what the user described; ask when the
  structure or a relationship is unclear.
