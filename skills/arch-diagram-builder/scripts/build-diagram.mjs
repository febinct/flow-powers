#!/usr/bin/env node
// build-diagram.mjs — wrap an inline SVG diagram into a self-contained, themeable
// HTML file (dark/light toggle + PNG/SVG export). Zero dependencies (Node fs only).
//
// The SVG you pass is authored by the agent (see SKILL.md): it uses the semantic
// classes .node/.label/.edge/… which the template themes via CSS variables, so
// one diagram renders correctly in both themes and exports standalone.
//
//   node build-diagram.mjs --svg diagram.svg --title "Payment flow" --out out.html
//   cat diagram.svg | node build-diagram.mjs --title "Payment flow" --out out.html
//
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const TEMPLATE = join(HERE, 'template.html');

function parseArgs(argv) {
  const a = {};
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    if (k === '--svg') a.svg = argv[++i];
    else if (k === '--title') a.title = argv[++i];
    else if (k === '--out') a.out = argv[++i];
    else if (k === '-h' || k === '--help') a.help = true;
  }
  return a;
}

function escapeHtml(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.out) {
    console.error('usage: build-diagram.mjs --title "<title>" --out <file.html> [--svg <file.svg>]');
    console.error('       (SVG may also be piped on stdin)');
    return args.help ? 0 : 2;
  }
  const title = args.title || 'Diagram';
  let svg = args.svg ? readFileSync(args.svg, 'utf8') : readFileSync(0, 'utf8');
  svg = svg.trim();
  if (!/^<svg[\s>]/i.test(svg)) {
    console.error('error: input does not start with an <svg> element');
    return 1;
  }
  // ensure the svg is a valid standalone root for export
  if (!/xmlns=/.test(svg)) svg = svg.replace(/^<svg/i, '<svg xmlns="http://www.w3.org/2000/svg"');

  const tpl = readFileSync(TEMPLATE, 'utf8');
  const html = tpl
    .replace(/__TITLE__/g, escapeHtml(title))
    .replace('__DIAGRAM_SVG__', svg);

  writeFileSync(args.out, html);
  console.error(`wrote: ${args.out} (${(Buffer.byteLength(html) / 1024).toFixed(1)} KB, self-contained)`);
  return 0;
}

process.exit(main());
