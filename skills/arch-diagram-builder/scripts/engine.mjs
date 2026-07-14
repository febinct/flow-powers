// engine.mjs — deterministic diagram engine (validate → layout → render).
// JSON IR in, computed geometry + SVG out. Zero dependencies.
//
// IR shape (see schemas/ and examples/):
//   { type, title, nodes:[{id,label,cat?,row?,col?,lane?,phase?}],
//     edges:[{from,to,label?,kind?}], lanes?:[], phases?:[], actors?:[] }
// kinds: normal | async | exception | happy   cats: frontend|backend|database|cloud|security|queue|external
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const TYPES = ['architecture', 'dataflow', 'lifecycle', 'workflow', 'sequence'];
export const CATS = ['frontend', 'backend', 'database', 'cloud', 'security', 'queue', 'external'];
export const KINDS = ['normal', 'async', 'exception', 'happy'];

const CHAR_W = 8.2, PAD_X = 26, MIN_W = 96, NODE_H = 48;
const GAP_X = 70, GAP_Y = 36, MARGIN = 32, LANE_LABEL_W = 132, PHASE_HEAD_H = 34;

const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
// CJK / full-width glyphs render ~1.8× a Latin char — count them so labels in
// those scripts don't get clipped by an underestimated box width.
function charUnits(ch) {
  const c = ch.codePointAt(0);
  const wide = (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3)
    || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60) || (c >= 0xffe0 && c <= 0xffe6);
  return wide ? 1.8 : 1;
}
function nodeW(label) { let u = 0; for (const ch of String(label || '')) u += charUnits(ch); return Math.max(MIN_W, Math.round(u * CHAR_W + PAD_X * 2)); }

// ---------------------------------------------------------------- validation
export function validate(ir) {
  const errors = [], warnings = [];
  const err = (msg, hint) => errors.push({ msg, hint });
  const warn = (msg, hint) => warnings.push({ msg, hint });

  if (!ir || typeof ir !== 'object') { err('IR is not an object', 'pass a parsed JSON object'); return { errors, warnings }; }
  if (!TYPES.includes(ir.type)) err(`type "${ir.type}" is not valid`, `use one of: ${TYPES.join(', ')}`);
  if (typeof ir.title !== 'string' || !ir.title.trim()) warn('missing title', 'add a short "title" string');
  if (!Array.isArray(ir.nodes) || ir.nodes.length === 0) { err('nodes must be a non-empty array', 'add at least one node'); return { errors, warnings }; }

  const ids = new Set();
  ir.nodes.forEach((n, i) => {
    if (!n || typeof n.id !== 'string') return err(`nodes[${i}].id missing`, 'every node needs a unique string id');
    if (ids.has(n.id)) err(`duplicate node id "${n.id}"`, 'ids must be unique');
    ids.add(n.id);
    if (typeof n.label !== 'string' || !n.label) warn(`node "${n.id}" has no label`, 'add a human-readable label');
    if (n.cat && !CATS.includes(n.cat)) warn(`node "${n.id}" cat "${n.cat}" unknown`, `use one of: ${CATS.join(', ')}`);
  });

  const edges = Array.isArray(ir.edges) ? ir.edges : [];
  edges.forEach((e, i) => {
    if (!e || typeof e !== 'object') return err(`edges[${i}] is not an object`);
    if (!ids.has(e.from)) err(`edge[${i}] from "${e.from}" is not a node id`, 'reference an existing node id');
    if (!ids.has(e.to)) err(`edge[${i}] to "${e.to}" is not a node id`, 'reference an existing node id');
    if (e.kind && !KINDS.includes(e.kind)) warn(`edge[${i}] kind "${e.kind}" unknown`, `use one of: ${KINDS.join(', ')}`);
  });

  if (ir.type === 'workflow') {
    const missing = ir.nodes.filter(n => !n.lane || n.phase == null);
    if (missing.length) warn(`${missing.length} workflow node(s) missing lane/phase`, 'give each node a "lane" and a "phase" for swimlane layout');
  }
  if (ir.type === 'sequence' && edges.length === 0) warn('sequence has no messages', 'add edges (messages) between actors');
  return { errors, warnings };
}

// ---------------------------------------------------------------- layout
// each layout returns { width, height, nodes:{id:{x,y,w,h,label,cls}}, edges:[{from,to,label,kind}], decorations:[] }
function rankNodes(ir) {
  // longest-path layering from sources; back-edges (cycles) ignored for ranking
  const incoming = {}, adj = {};
  ir.nodes.forEach(n => { incoming[n.id] = 0; adj[n.id] = []; });
  (ir.edges || []).forEach(e => { if (adj[e.from] && incoming[e.to] != null) { adj[e.from].push(e.to); incoming[e.to]++; } });
  const rank = {}; const q = ir.nodes.filter(n => incoming[n.id] === 0).map(n => n.id);
  ir.nodes.forEach(n => rank[n.id] = 0);
  if (q.length === 0 && ir.nodes.length) q.push(ir.nodes[0].id); // pure cycle → seed
  const seen = new Set(); let head = 0; const order = [...q];
  while (head < order.length) {
    const id = order[head++]; if (seen.has(id)) continue; seen.add(id);
    for (const t of adj[id]) { rank[t] = Math.max(rank[t], rank[id] + 1); if (!seen.has(t)) order.push(t); }
  }
  return rank;
}

function layeredLayout(ir) {
  const gridMode = ir.nodes.every(n => Number.isInteger(n.col));
  const col = {}, rowIdx = {};
  if (gridMode) {
    ir.nodes.forEach(n => { col[n.id] = n.col; rowIdx[n.id] = Number.isInteger(n.row) ? n.row : 0; });
  } else {
    const rank = rankNodes(ir); const perCol = {};
    ir.nodes.forEach(n => { col[n.id] = rank[n.id]; perCol[rank[n.id]] = (perCol[rank[n.id]] || 0); rowIdx[n.id] = perCol[rank[n.id]]++; });
  }
  const cols = [...new Set(ir.nodes.map(n => col[n.id]))].sort((a, b) => a - b);
  const colW = {}, colX = {};
  cols.forEach(c => { colW[c] = Math.max(...ir.nodes.filter(n => col[n.id] === c).map(n => nodeW(n.label || n.id))); });
  let x = MARGIN; cols.forEach(c => { colX[c] = x; x += colW[c] + GAP_X; });
  const nodes = {};
  ir.nodes.forEach(n => {
    const c = col[n.id], w = nodeW(n.label || n.id);
    nodes[n.id] = { x: colX[c] + (colW[c] - w) / 2, y: MARGIN + rowIdx[n.id] * (NODE_H + GAP_Y), w, h: NODE_H,
      label: n.label || n.id, cls: n.cat ? `cat-${n.cat}` : 'node' };
  });
  const maxRow = Math.max(...Object.values(rowIdx));
  return { width: x - GAP_X + MARGIN, height: MARGIN * 2 + (maxRow + 1) * NODE_H + maxRow * GAP_Y,
    nodes, edges: ir.edges || [], decorations: [] };
}

function workflowLayout(ir) {
  // lanes may be strings or { name, variant:"exception" }
  const laneDefs = (ir.lanes && ir.lanes.length ? ir.lanes : [...new Set(ir.nodes.map(n => n.lane || 'default'))])
    .map(l => typeof l === 'string' ? { name: l } : l);
  const lanes = laneDefs.map(l => l.name);
  const phases = ir.phases && ir.phases.length ? ir.phases
    : [...new Set(ir.nodes.map(n => n.phase))].filter(p => p != null).sort((a, b) => a - b);
  const phaseList = phases.length ? phases : [0];
  const STACK_GAP = 14;
  // group nodes by (lane, phase) cell so multiple nodes in one cell stack instead of overlap
  const cell = {}; const li = n => Math.max(0, lanes.indexOf(n.lane || 'default'));
  ir.nodes.forEach(n => { const k = li(n) + ':' + phaseIdx(n, phaseList); (cell[k] = cell[k] || []).push(n); });
  // per-lane height = tallest stack in that lane; column width = widest node in that phase
  const laneRows = lanes.map((_, l) => Math.max(1, ...phaseList.map((_, p) => (cell[l + ':' + p] || []).length)));
  const laneH = laneRows.map(r => r * NODE_H + (r - 1) * STACK_GAP + GAP_Y);
  const laneY = []; let y = PHASE_HEAD_H; lanes.forEach((_, l) => { laneY[l] = y; y += laneH[l]; });
  const colW = {}; phaseList.forEach((p, pi) => { colW[pi] = Math.max(MIN_W, ...ir.nodes.filter(n => phaseIdx(n, phaseList) === pi).map(n => nodeW(n.label || n.id))); });
  const colX = {}; let x = LANE_LABEL_W; phaseList.forEach((p, pi) => { colX[pi] = x; x += colW[pi] + GAP_X; });
  const width = x - GAP_X + MARGIN, height = y + MARGIN;
  const decorations = [];
  lanes.forEach((ln, l) => decorations.push({ kind: 'lane', label: ln, x: 0, y: laneY[l], w: width, h: laneH[l], band: l % 2, variant: laneDefs[l].variant }));
  phaseList.forEach((p, pi) => { if (phases.length) decorations.push({ kind: 'phase', label: String(p), x: colX[pi], y: 4, w: colW[pi] }); });
  const nodes = {};
  Object.entries(cell).forEach(([k, group]) => {
    const [l, pi] = k.split(':').map(Number);
    const stackH = group.length * NODE_H + (group.length - 1) * STACK_GAP;
    const y0 = laneY[l] + (laneH[l] - stackH) / 2;
    group.forEach((n, si) => { const w = nodeW(n.label || n.id);
      nodes[n.id] = { x: colX[pi] + (colW[pi] - w) / 2, y: y0 + si * (NODE_H + STACK_GAP), w, h: NODE_H,
        label: n.label || n.id, cls: n.cat ? `cat-${n.cat}` : 'node' };
    });
  });
  return { width, height, nodes, edges: ir.edges || [], decorations };
}
const phaseIdx = (n, phaseList) => { const i = phaseList.indexOf(n.phase); return i < 0 ? 0 : i; };

function sequenceLayout(ir) {
  const actors = ir.actors && ir.actors.length ? ir.actors : ir.nodes.map(n => n.id);
  const colGap = 190, msgGap = 62, topH = MARGIN + NODE_H;
  const nodes = {}, decorations = [];
  const byId = Object.fromEntries(ir.nodes.map(n => [n.id, n]));
  const height = topH + (ir.edges || []).length * msgGap + msgGap;
  actors.forEach((id, i) => {
    const n = byId[id] || { label: id }, w = Math.max(MIN_W, nodeW(n.label || id)), cx = MARGIN + i * colGap + w / 2;
    nodes[id] = { x: MARGIN + i * colGap, y: MARGIN, w, h: NODE_H, label: n.label || id, cls: n.cat ? `cat-${n.cat}` : 'node', cx };
    decorations.push({ kind: 'lifeline', x: cx, y1: MARGIN + NODE_H, y2: height - MARGIN / 2 });
  });
  const edges = (ir.edges || []).map((e, i) => ({ ...e, seqY: topH + (i + 1) * msgGap }));
  return { width: MARGIN * 2 + Math.max(1, actors.length) * colGap - (colGap - Math.max(...actors.map(a => nodes[a].w))), height, nodes, edges, decorations, sequence: true };
}

export function layout(ir) {
  if (ir.type === 'workflow') return workflowLayout(ir);
  if (ir.type === 'sequence') return sequenceLayout(ir);
  return layeredLayout(ir); // architecture | dataflow | lifecycle
}

const sidePt = (box, side) => {
  const cx = box.x + box.w / 2, cy = box.y + box.h / 2;
  return side === 'left' ? { x: box.x, y: cy } : side === 'right' ? { x: box.x + box.w, y: cy }
    : side === 'top' ? { x: cx, y: box.y } : { x: cx, y: box.y + box.h };
};

// orthogonal route between two boxes → list of points. `e.fromSide`/`e.toSide`
// (left|right|top|bottom) override the auto-picked attachment sides.
function route(a, b, e = {}) {
  if (e.fromSide || e.toSide) {
    const fwd = (b.x + b.w / 2) >= (a.x + a.w / 2);
    const fs = e.fromSide || (fwd ? 'right' : 'left'), ts = e.toSide || (fwd ? 'left' : 'right');
    const p = sidePt(a, fs), q = sidePt(b, ts), horizFrom = fs === 'left' || fs === 'right';
    return horizFrom ? [p, { x: (p.x + q.x) / 2, y: p.y }, { x: (p.x + q.x) / 2, y: q.y }, q]
      : [p, { x: p.x, y: (p.y + q.y) / 2 }, { x: q.x, y: (p.y + q.y) / 2 }, q];
  }
  const ax = a.x + a.w / 2, ay = a.y + a.h / 2, bx = b.x + b.w / 2, by = b.y + b.h / 2;
  if (Math.abs(ay - by) < a.h) { // same band → horizontal
    const [l, r] = ax < bx ? [a, b] : [b, a];
    return ax < bx ? [{ x: a.x + a.w, y: ay }, { x: b.x, y: by }] : [{ x: a.x, y: ay }, { x: b.x + b.w, y: by }];
  }
  if (Math.abs(ax - bx) < a.w) { // same column → vertical
    return ay < by ? [{ x: ax, y: a.y + a.h }, { x: bx, y: b.y }] : [{ x: ax, y: a.y }, { x: bx, y: b.y + b.h }];
  }
  // general: exit the source SIDE, run the vertical leg in the column GAP (never
  // through a column's nodes), then enter the target's side. This avoids the
  // fan-out-into-a-column crossing.
  const forward = bx >= ax;
  const sx = forward ? a.x + a.w : a.x, tx = forward ? b.x : b.x + b.w;
  // vertical leg sits in the gap immediately beside the SOURCE, so a multi-column
  // span doesn't drop through an intermediate node; the horizontal leg runs at
  // the target's row (clear of the source row's nodes).
  const midX = forward ? sx + GAP_X / 2 : sx - GAP_X / 2;
  return [{ x: sx, y: ay }, { x: midX, y: ay }, { x: midX, y: by }, { x: tx, y: by }];
}

// ---------------------------------------------------------------- layout report (overlap / bounds / crossings)
export function layoutReport(lay) {
  const warnings = [];
  const ns = Object.entries(lay.nodes).map(([id, n]) => ({ id, ...n }));
  for (let i = 0; i < ns.length; i++) for (let j = i + 1; j < ns.length; j++) {
    const a = ns[i], b = ns[j];
    if (a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)
      warnings.push({ msg: `nodes "${a.id}" and "${b.id}" overlap`, hint: 'give them different row/col (or lane/phase)' });
  }
  ns.forEach(n => { if (n.x < 0 || n.y < 0 || n.x + n.w > lay.width + 1 || n.y + n.h > lay.height + 1)
    warnings.push({ msg: `node "${n.id}" is outside the canvas`, hint: 'layout bug or bad explicit row/col' }); });
  if (!lay.sequence) (lay.edges || []).forEach(e => {
    const a = lay.nodes[e.from], b = lay.nodes[e.to]; if (!a || !b) return;
    const pts = route(a, b, e);
    for (const n of ns) { if (n.id === e.from || n.id === e.to) continue;
      for (let k = 0; k < pts.length - 1; k++) if (segHitsBox(pts[k], pts[k + 1], n)) {
        warnings.push({ msg: `edge ${e.from}→${e.to} crosses node "${n.id}"`, hint: 'reorder nodes or set explicit row/col' }); break;
      }
    }
  });
  return { warnings };
}
function segHitsBox(p, q, n) {
  const minX = Math.min(p.x, q.x), maxX = Math.max(p.x, q.x), minY = Math.min(p.y, q.y), maxY = Math.max(p.y, q.y);
  return maxX > n.x + 4 && minX < n.x + n.w - 4 && maxY > n.y + 4 && minY < n.y + n.h - 4;
}

// ---------------------------------------------------------------- render → SVG
const markerFor = { normal: 'arrow', happy: 'arrow-accent', async: 'arrow', exception: 'arrow-exc' };
function edgeClass(kind, animate) {
  const base = kind === 'exception' ? 'edge edge-exception' : kind === 'happy' ? 'edge edge-happy' : 'edge';
  return (animate || kind === 'happy') ? base + ' edge-flow' : base;
}

const CAT_LABEL = { frontend: 'Frontend', backend: 'Backend', database: 'Database', cloud: 'Cloud/Infra', security: 'Security', queue: 'Queue/Cache', external: 'External' };

export function render(ir, lay) {
  const animate = !!ir.animate;
  const catsUsed = [...new Set(Object.values(lay.nodes).map(n => n.cls).filter(c => c.startsWith('cat-')).map(c => c.slice(4)))];
  const showLegend = ir.legend !== false && catsUsed.length > 0;
  const legendH = showLegend ? 46 : 0;
  const parts = [];
  parts.push(`<svg viewBox="0 0 ${Math.ceil(lay.width)} ${Math.ceil(lay.height + legendH)}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${esc(ir.title || ir.type + ' diagram')}" data-animate="${animate ? 'on' : 'off'}" font-family="sans-serif">`);
  parts.push(`<defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="var(--edge)"/></marker>
    <marker id="arrow-accent" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="var(--accent)"/></marker>
    <marker id="arrow-exc" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#f43f5e"/></marker>
  </defs>`);
  // decorations first (behind nodes)
  for (const d of lay.decorations || []) {
    if (d.kind === 'lane') {
      const exc = d.variant === 'exception';
      parts.push(`<rect x="${d.x}" y="${d.y}" width="${d.w}" height="${d.h}" class="lane ${exc ? 'lane-exception' : d.band ? 'lane-alt' : ''}"/>`);
      parts.push(`<text x="12" y="${d.y + d.h / 2 + 4}" class="lane-label">${exc ? 'EX · ' : ''}${esc(d.label)}</text>`);
    }
    if (d.kind === 'phase') parts.push(`<text x="${d.x + d.w / 2}" y="${d.y + 18}" text-anchor="middle" class="phase-label">${esc(d.label)}</text>`);
    if (d.kind === 'lifeline') parts.push(`<line x1="${d.x}" y1="${d.y1}" x2="${d.x}" y2="${d.y2}" class="lifeline"/>`);
  }
  // edges
  if (lay.sequence) {
    for (const e of lay.edges) {
      const a = lay.nodes[e.from], b = lay.nodes[e.to]; if (!a || !b) continue;
      const y = e.seqY, cls = edgeClass(e.kind, animate), mk = markerFor[e.kind] || 'arrow';
      if (a.cx === b.cx) { parts.push(`<path class="${cls}" d="M${a.cx} ${y} h40 v20 h-40" marker-end="url(#${mk})"/>`); }
      else parts.push(`<line class="${cls}" x1="${a.cx}" y1="${y}" x2="${b.cx}" y2="${y}" marker-end="url(#${mk})"/>`);
      if (e.label) parts.push(`<text x="${(a.cx + b.cx) / 2}" y="${y - 6}" text-anchor="middle" class="edge-label">${esc(e.label)}</text>`);
    }
  } else {
    for (const e of lay.edges) {
      const a = lay.nodes[e.from], b = lay.nodes[e.to]; if (!a || !b) continue;
      const pts = route(a, b, e), d = 'M' + pts.map(p => `${Math.round(p.x)} ${Math.round(p.y)}`).join(' L');
      parts.push(`<path class="${edgeClass(e.kind, animate)}" d="${d}" fill="none" marker-end="url(#${markerFor[e.kind] || 'arrow'})"${e.kind === 'async' ? ' stroke-dasharray="6 5"' : ''}/>`);
      if (e.label) { const m = pts[Math.floor(pts.length / 2) - (pts.length > 2 ? 0 : 0)] || pts[0], m2 = pts[Math.floor((pts.length - 1) / 2)];
        parts.push(`<text x="${Math.round((m2.x))}" y="${Math.round(m2.y) - 6}" text-anchor="middle" class="edge-label">${esc(e.label)}</text>`); }
    }
  }
  // nodes
  for (const [id, n] of Object.entries(lay.nodes)) {
    parts.push(`<rect x="${Math.round(n.x)}" y="${Math.round(n.y)}" width="${n.w}" height="${n.h}" rx="10" class="${n.cls}"/>`);
    parts.push(`<text x="${Math.round(n.x + n.w / 2)}" y="${Math.round(n.y + n.h / 2 + 5)}" text-anchor="middle" class="label">${esc(n.label)}</text>`);
  }
  // legend (category key), laid out left→right along the bottom band
  if (showLegend) {
    let lx = MARGIN; const ly = Math.ceil(lay.height) + 14;
    parts.push(`<g class="legend" role="list" aria-label="Legend">`);
    for (const cat of catsUsed) {
      const label = CAT_LABEL[cat] || cat;
      parts.push(`<rect x="${lx}" y="${ly}" width="16" height="16" rx="4" class="cat-${cat}"/>`);
      parts.push(`<text x="${lx + 22}" y="${ly + 13}" class="edge-label">${esc(label)}</text>`);
      lx += 22 + label.length * 7 + 26;
    }
    parts.push('</g>');
  }
  parts.push('</svg>');
  return parts.join('\n');
}

// ---------------------------------------------------------------- html wrap (shared with build-diagram.mjs)
export function wrapHtml(svg, title) {
  const HERE = dirname(fileURLToPath(import.meta.url));
  const tpl = readFileSync(join(HERE, 'template.html'), 'utf8');
  let s = svg.trim();
  if (!/xmlns=/.test(s)) s = s.replace(/^<svg/i, '<svg xmlns="http://www.w3.org/2000/svg"');
  return tpl.replace(/__TITLE__/g, esc(title || 'Diagram')).replace('__DIAGRAM_SVG__', s);
}

export function parseIR(text) { const ir = JSON.parse(text); return ir; }

// ---------------------------------------------------------------- post-render artifact check
// Inspect a RENDERED html file (not the IR) for the ways a render can go wrong.
export function checkOutput(html) {
  const checks = [];
  const add = (name, ok, detail) => checks.push({ name, ok, detail });
  const svgs = html.match(/<svg\b[\s\S]*?<\/svg>/gi) || [];
  add('single_svg', svgs.length === 1, `found ${svgs.length} <svg> block(s)`);
  const svg = svgs[0] || '';
  add('finite_coords', !/\b(NaN|undefined|Infinity|-Infinity)\b/.test(svg), 'no NaN/undefined/Infinity in the SVG');
  add('has_viewbox', /<svg[^>]*\bviewBox="/.test(svg), 'root <svg> has a viewBox');
  add('no_placeholders', !/__TITLE__|__DIAGRAM_SVG__/.test(html), 'template placeholders were replaced');
  add('self_contained', !/(src|href)\s*=\s*"https?:|@import[^;]*https?:/i.test(html), 'no external network references');
  add('has_content', /<rect\b/.test(svg) || /<line\b/.test(svg) || /<path\b/.test(svg), 'SVG contains drawn shapes');
  add('theme_ready', /data-animate=|--node|prefers-color-scheme/.test(html), 'theme/runtime present');
  return { checks, ok: checks.every(c => c.ok) };
}
