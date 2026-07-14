#!/usr/bin/env node
// diagram.mjs — CLI for the deterministic diagram engine.
//
//   diagram render   <ir.json> --out <file.html> [--animate] [--strict]
//   diagram validate <ir.json> [--strict]        # schema + layout report
//   diagram inspect  <ir.json>                    # print computed layout JSON
//   diagram examples --out-dir <dir>              # write one example IR per type
//   diagram demo     [--out <file.html>]          # render a bundled example
//   diagram doctor                                # environment + self-test
//
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { validate, layout, layoutReport, render, wrapHtml, standaloneSvg, parseIR, checkOutput, TYPES } from './engine.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const EX_DIR = join(HERE, 'examples');
const args = process.argv.slice(2);
const cmd = args[0];
const flag = (name) => { const i = args.indexOf(name); return i >= 0 ? (args[i + 1] || true) : undefined; };
const has = (name) => args.includes(name);
const posArg = () => args.slice(1).find(a => !a.startsWith('--'));
const red = (s) => `\x1b[31m${s}\x1b[0m`, yel = (s) => `\x1b[33m${s}\x1b[0m`, grn = (s) => `\x1b[32m${s}\x1b[0m`;

function printIssues(v) {
  v.errors.forEach(e => console.error(red('  ✘ ' + e.msg) + (e.hint ? ` — ${e.hint}` : '')));
  v.warnings.forEach(w => console.error(yel('  ⚠ ' + w.msg) + (w.hint ? ` — ${w.hint}` : '')));
}

function loadIR(path) {
  if (!path) { console.error('error: provide an IR JSON file path'); process.exit(2); }
  return parseIR(readFileSync(path, 'utf8'));
}

function checkOrExit(ir, strict) {
  const v = validate(ir);
  const lay = v.errors.length ? null : layout(ir);
  const rep = lay ? layoutReport(lay) : { warnings: [] };
  const all = { errors: v.errors, warnings: [...v.warnings, ...rep.warnings] };
  printIssues(all);
  if (all.errors.length) { console.error(red(`\n${all.errors.length} error(s) — not rendering.`)); process.exit(1); }
  if (strict && all.warnings.length) { console.error(red(`\n--strict: ${all.warnings.length} warning(s) treated as errors.`)); process.exit(1); }
  return { lay: lay || layout(ir), warnings: all.warnings };
}

switch (cmd) {
  case 'render': {
    const ir = loadIR(posArg());
    if (has('--animate')) ir.animate = true;
    const { lay } = checkOrExit(ir, has('--strict'));
    const out = flag('--out'); if (!out) { console.error('error: --out <file.html> required'); process.exit(2); }
    const html = wrapHtml(render(ir, lay), ir.title);
    writeFileSync(out, html);
    console.error(grn(`wrote: ${out}`) + ` (${(Buffer.byteLength(html) / 1024).toFixed(1)} KB, self-contained; ${Object.keys(lay.nodes).length} nodes)`);
    break;
  }
  case 'validate': {
    const ir = loadIR(posArg());
    const v = validate(ir);
    const rep = v.errors.length ? { warnings: [] } : layoutReport(layout(ir));
    printIssues({ errors: v.errors, warnings: [...v.warnings, ...rep.warnings] });
    const nErr = v.errors.length, nWarn = v.warnings.length + rep.warnings.length;
    if (nErr) { console.error(red(`\nFAIL: ${nErr} error(s), ${nWarn} warning(s)`)); process.exit(1); }
    if (has('--strict') && nWarn) { console.error(red(`\nFAIL (--strict): ${nWarn} warning(s)`)); process.exit(1); }
    console.error(grn(`OK: valid ${ir.type} (${nWarn} warning(s))`));
    break;
  }
  case 'svg': {
    const ir = loadIR(posArg());
    const v = validate(ir); if (v.errors.length) { printIssues(v); process.exit(1); }
    const out = flag('--out'); if (!out) { console.error('error: --out <file.svg> required'); process.exit(2); }
    writeFileSync(out, standaloneSvg(ir, layout(ir)) + '\n');
    console.error(grn(`wrote: ${out}`) + ' (standalone dual-theme SVG)');
    break;
  }
  case 'check': {
    const path = posArg(); if (!path) { console.error('error: provide a rendered .html file'); process.exit(2); }
    const { checks, ok } = checkOutput(readFileSync(path, 'utf8'));
    checks.forEach(c => console.error((c.ok ? grn('  ok ') : red('  ✘  ')) + c.name + (c.detail ? ` — ${c.detail}` : '')));
    console.error(ok ? grn('\ncheck: rendered output OK') : red('\ncheck: problems found'));
    process.exit(ok ? 0 : 1);
  }
  case 'inspect': {
    const ir = loadIR(posArg());
    const v = validate(ir); if (v.errors.length) { printIssues(v); process.exit(1); }
    const lay = layout(ir);
    console.log(JSON.stringify({ type: ir.type, width: lay.width, height: lay.height,
      nodes: Object.fromEntries(Object.entries(lay.nodes).map(([id, n]) => [id, { x: Math.round(n.x), y: Math.round(n.y), w: n.w, h: n.h }])),
      decorations: (lay.decorations || []).map(d => d.kind), report: layoutReport(lay).warnings.map(w => w.msg) }, null, 2));
    break;
  }
  case 'examples': {
    const dir = flag('--out-dir') || EX_DIR; mkdirSync(dir, { recursive: true });
    for (const t of TYPES) { const src = join(EX_DIR, `${t}.json`); const dst = join(dir, `${t}.json`);
      if (src !== dst) writeFileSync(dst, readFileSync(src)); console.error(grn(`example: ${dst}`)); }
    break;
  }
  case 'demo': {
    const ir = parseIR(readFileSync(join(EX_DIR, 'architecture.json'), 'utf8'));
    const out = flag('--out') || join(process.cwd(), 'diagram-demo.html');
    writeFileSync(out, wrapHtml(render(ir, layout(ir)), ir.title));
    console.error(grn(`demo rendered: ${out}`));
    break;
  }
  case 'doctor': {
    let ok = true;
    const line = (good, msg) => { console.error((good ? grn('  ok ') : red('  ✘  ')) + msg); if (!good) ok = false; };
    const [maj] = process.versions.node.split('.').map(Number);
    line(maj >= 18, `node ${process.versions.node} (need ≥18)`);
    try { readFileSync(join(HERE, 'template.html')); line(true, 'template.html present'); } catch { line(false, 'template.html missing'); }
    try { const ir = parseIR(readFileSync(join(EX_DIR, 'architecture.json'), 'utf8'));
      const html = wrapHtml(render(ir, layout(ir)), ir.title);
      line(/<svg/.test(html) && !/__DIAGRAM_SVG__/.test(html), 'self-test render (architecture example)');
    } catch (e) { line(false, 'self-test render: ' + e.message); }
    console.error(ok ? grn('\ndoctor: all checks passed') : red('\ndoctor: problems found'));
    process.exit(ok ? 0 : 1);
  }
  default:
    console.error(`diagram — deterministic diagram engine\n
  render   <ir.json> --out <file.html> [--animate] [--strict]
  validate <ir.json> [--strict]
  check    <file.html>                # post-render artifact check
  inspect  <ir.json>
  examples --out-dir <dir>
  demo     [--out <file.html>]
  doctor
\ntypes: ${TYPES.join(', ')}`);
    process.exit(cmd && cmd !== 'help' ? 2 : 0);
}
