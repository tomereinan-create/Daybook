import { writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

/// A "D" drawn as geometry rather than type, so it rasterises cleanly at every
/// size the system asks for. The letterform is a rectangle whose right side is
/// a semicircle, minus the same shape inset by the stroke width — which is
/// what a D actually is.

const SIZE = 1024;
const SS = 4; // supersampling per axis

// The app's palette: clay ground, warm paper letter.
const BG = [0xb4, 0x53, 0x1f];
const FG = [0xfa, 0xf8, 0xf3];

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

writeFileSync(process.argv[2], png);
console.log(`wrote ${process.argv[2]} — ${SIZE}x${SIZE}, ${(png.length / 1024).toFixed(1)} KB`);
