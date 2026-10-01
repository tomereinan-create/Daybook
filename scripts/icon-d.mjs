import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { deflateSync, inflateSync } from 'node:zlib';

/// A "D" drawn as geometry rather than type, so it rasterises cleanly at every
/// size the system asks for. The letterform is a rectangle whose right side is
/// a semicircle, minus the same shape inset by the stroke width — which is
/// what a D actually is.
///
/// The ground colour changes with every build, so the icon on the home screen
/// says which one is installed without opening anything. The colour is not
/// random: it is entry `index` of the palette below, and `index` is committed,
/// so the same commit always produces the same icon. CI checks the committed
/// icon against that index, which is what stops the two drifting apart.
///
///   node scripts/icon-d.mjs          regenerate at the committed index
///   node scripts/icon-d.mjs --next   advance one colour, then regenerate
///   node scripts/icon-d.mjs --check  verify what is committed, write nothing

// Every one of these is dark enough for the warm-paper letter to read at the
// smallest size the system draws, and far enough from its neighbours in the
// list to be told apart across a week of builds.
const PALETTE = [
  { name: 'Clay',   rgb: [0xb4, 0x53, 0x1f] },
  { name: 'Teal',   rgb: [0x12, 0x71, 0x6b] },
  { name: 'Indigo', rgb: [0x3b, 0x3d, 0x8f] },
  { name: 'Plum',   rgb: [0x7a, 0x2e, 0x5e] },
  { name: 'Moss',   rgb: [0x3f, 0x6b, 0x2b] },
  { name: 'Slate',  rgb: [0x3a, 0x4a, 0x5a] },
  { name: 'Rust',   rgb: [0x93, 0x33, 0x1f] },
  { name: 'Ochre',  rgb: [0x96, 0x70, 0x1a] },
  { name: 'Ocean',  rgb: [0x17, 0x55, 0x7e] },
  { name: 'Vine',   rgb: [0x5b, 0x2e, 0x86] },
  { name: 'Pine',   rgb: [0x1f, 0x5f, 0x45] },
  { name: 'Brick',  rgb: [0x8e, 0x2f, 0x3c] },
  // Sits between Brick and the wrap back to Clay, which are both reds and
  // too close to tell apart at the size an icon is actually looked at.
  { name: 'Graphite', rgb: [0x3f, 0x3f, 0x46] },
];

const INDEX_FILE = 'scripts/icon-color.json';
const ICON_FILE = 'App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png';
const SWIFT_FILE = 'Core/Generated/BuildColor.swift';

const advance = process.argv.includes('--next');
const checkOnly = process.argv.includes('--check');
const stored = JSON.parse(readFileSync(INDEX_FILE, 'utf8'));
const index = (advance ? stored.index + 1 : stored.index) % PALETTE.length;
const colour = PALETTE[index];

const SIZE = 1024;
const SS = 4; // supersampling per axis

// Checking compares the colour, not the file's bytes. Two machines running
// the same script produce the same picture but not the same PNG: zlib's
// output varies between platforms and versions, so a byte comparison fails
// on an icon that is perfectly correct. What matters is what is on screen.
if (checkOnly) {
  const fail = (message) => {
    console.error(`${message}
  Run: node scripts/icon-d.mjs`);
    process.exit(1);
  };

  const png = readFileSync(ICON_FILE);
  let at = 8;
  let header = null;
  const idat = [];
  while (at < png.length) {
    const length = png.readUInt32BE(at);
    const type = png.subarray(at + 4, at + 8).toString('ascii');
    const body = png.subarray(at + 8, at + 8 + length);
    if (type === 'IHDR') header = body;
    if (type === 'IDAT') idat.push(body);
    at += 12 + length;
  }
  if (!header) fail(`${ICON_FILE} has no IHDR.`);

  const width = header.readUInt32BE(0);
  const height = header.readUInt32BE(4);
  const colourType = header[9];
  if (width !== SIZE || height !== SIZE) fail(`${ICON_FILE} is ${width}x${height}, expected ${SIZE}x${SIZE}.`);
  if (colourType !== 2) fail(`${ICON_FILE} is colour type ${colourType}; the App Store needs RGB with no alpha.`);

  // The first pixel of the first row is canvas, never letter, so it is the
  // ground colour. Row byte 0 is the filter, which is 0 on every row here.
  const raw = inflateSync(Buffer.concat(idat));
  const found = [raw[1], raw[2], raw[3]];
  const asHex = (c) => c.map((v) => v.toString(16).padStart(2, '0')).join('');
  if (asHex(found) !== asHex(colour.rgb)) {
    fail(
      `${ICON_FILE} is #${asHex(found)} but index ${index} of the palette is ` +
        `${colour.name} #${asHex(colour.rgb)}. The icon and the committed colour have drifted apart.`
    );
  }

  const swift = readFileSync(SWIFT_FILE, 'utf8');
  if (!swift.includes(`name = "${colour.name}"`) || !swift.includes(`hex = "${asHex(colour.rgb)}"`)) {
    fail(`${SWIFT_FILE} does not name ${colour.name} #${asHex(colour.rgb)}.`);
  }

  console.log(`${colour.name} (#${asHex(colour.rgb)}) — index ${index}: icon and Settings agree.`);
  process.exit(0);
}

const BG = colour.rgb;
const FG = [0xfa, 0xf8, 0xf3]; // warm paper, the same on every colour

// Glyph box. Kept well inside the canvas so the system's corner mask and the
// various platform crops never clip it.
const H = 540;
const W = 430;
const STROKE = 98;

const top = (SIZE - H) / 2;
const bottom = top + H;
const cy = SIZE / 2;
const left = (SIZE - W) / 2;
const radius = H / 2;
const bowlCentreX = left + (W - radius);

const innerRadius = radius - STROKE;
const innerTop = top + STROKE;
const innerBottom = bottom - STROKE;
const innerLeft = left + STROKE;

function insideOuter(x, y) {
  if (y < top || y > bottom || x < left) return false;
  if (x <= bowlCentreX) return true;
  const dx = x - bowlCentreX;
  const dy = y - cy;
  return dx * dx + dy * dy <= radius * radius;
}

function insideCounter(x, y) {
  if (y < innerTop || y > innerBottom || x < innerLeft) return false;
  if (x <= bowlCentreX) return true;
  const dx = x - bowlCentreX;
  const dy = y - cy;
  return dx * dx + dy * dy <= innerRadius * innerRadius;
}

/** 0..1 coverage of the letter at this pixel. */
function coverage(px, py) {
  let hits = 0;
  for (let sy = 0; sy < SS; sy += 1) {
    for (let sx = 0; sx < SS; sx += 1) {
      const x = px + (sx + 0.5) / SS;
      const y = py + (sy + 0.5) / SS;
      if (insideOuter(x, y) && !insideCounter(x, y)) hits += 1;
    }
  }
  return hits / (SS * SS);
}

// ---- PNG encoding -----------------------------------------------------------

let table = null;
function crc32(buf) {
  if (!table) {
    table = new Int32Array(256);
    for (let n = 0; n < 256; n += 1) {
      let c = n;
      for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c;
    }
  }
  let c = -1;
  for (let i = 0; i < buf.length; i += 1) c = table[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return c ^ -1;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body) >>> 0);
  return Buffer.concat([len, body, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8;  // bit depth
ihdr[9] = 2;  // truecolour, no alpha: app icons must be fully opaque
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;

const rows = [];
for (let y = 0; y < SIZE; y += 1) {
  const row = Buffer.alloc(1 + SIZE * 3);
  for (let x = 0; x < SIZE; x += 1) {
    const a = coverage(x, y);
    const o = 1 + x * 3;
    for (let c = 0; c < 3; c += 1) {
      row[o + c] = Math.round(BG[c] * (1 - a) + FG[c] * a);
    }
  }
  rows.push(row);
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(Buffer.concat(rows), { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);

writeFileSync(ICON_FILE, png);

// The app says the same name out loud in Settings, so "which build am I on"
// can be answered without holding two home screens side by side.
const hex = BG.map((c) => c.toString(16).padStart(2, '0')).join('');
mkdirSync(dirname(SWIFT_FILE), { recursive: true });
writeFileSync(
  SWIFT_FILE,
  `// Generated by scripts/icon-d.mjs. Do not edit by hand.
//
// The app icon's colour changes with every build so the home screen says
// which one is installed. This is the same colour, by name, for the row in
// Settings that answers the same question in words.

import Foundation

nonisolated enum BuildColor {
    static let name = "${colour.name}"
    static let hex = "${hex}"
    static let red = ${(BG[0] / 255).toFixed(4)}
    static let green = ${(BG[1] / 255).toFixed(4)}
    static let blue = ${(BG[2] / 255).toFixed(4)}
}
`,
  'utf8'
);

if (advance) {
  writeFileSync(INDEX_FILE, `${JSON.stringify({ index }, null, 2)}\n`, 'utf8');
}

console.log(
  `${colour.name} (#${hex}) — index ${index} of ${PALETTE.length}` +
    `${advance ? ', advanced' : ''}\n` +
    `  ${ICON_FILE} — ${SIZE}x${SIZE}, ${(png.length / 1024).toFixed(1)} KB\n` +
    `  ${SWIFT_FILE}`
);
