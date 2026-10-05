import { writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

/// The Windows icon for the demo shortcut.
///
/// The same "D" as the app — a rectangle whose right side is a semicircle,
/// minus the same shape inset by the stroke width — drawn at the sizes
/// Windows picks between and packed into a .ico.
///
/// Deliberately a fixed colour rather than the app's rotating build colour.
/// That rotation exists to say which build is on the phone; a shortcut on a
/// desktop is not a build, and an icon that changed under you every time
/// would be worse than useless for finding it.
///
///   node scripts/demo-icon.mjs

const OUT = 'demo/daybook.ico';
const SIZES = [16, 24, 32, 48, 64, 128, 256];
const BG = [0xb4, 0x53, 0x1f]; // clay
const FG = [0xfa, 0xf8, 0xf3]; // warm paper

// Proportions of the 1024 design, as fractions, so every size is the same
// drawing rather than a separate decision.
const H = 540 / 1024;
const W = 430 / 1024;
const STROKE = 98 / 1024;

/** 0..1 coverage of the letterform at a point, in 0..1 space. */
function coverageAt(x, y) {
  const top = (1 - H) / 2;
  const bottom = top + H;
  const left = (1 - W) / 2;
  const radius = H / 2;
  const cy = 0.5;
  const bowl = left + (W - radius);

  const inside = (t, b, l, r) => {
    if (y < t || y > b || x < l) return false;
    if (x <= bowl) return true;
    const dx = x - bowl;
    const dy = y - cy;
    return dx * dx + dy * dy <= r * r;
  };

  const outer = inside(top, bottom, left, radius);
  const counter = inside(top + STROKE, bottom - STROKE, left + STROKE, radius - STROKE);
  return outer && !counter;
}

/** An RGBA bitmap of the glyph at `size`, supersampled. */
function render(size) {
  const ss = size <= 32 ? 6 : 4;
  const px = Buffer.alloc(size * size * 4);
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      let hits = 0;
      for (let sy = 0; sy < ss; sy += 1) {
        for (let sx = 0; sx < ss; sx += 1) {
          if (coverageAt((x + (sx + 0.5) / ss) / size, (y + (sy + 0.5) / ss) / size)) hits += 1;
        }
      }
      const a = hits / (ss * ss);
      const o = (y * size + x) * 4;
      for (let c = 0; c < 3; c += 1) px[o + c] = Math.round(BG[c] * (1 - a) + FG[c] * a);
      px[o + 3] = 255; // opaque: the whole tile is the icon
    }
  }
  return px;
}

// ---- PNG --------------------------------------------------------------------

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

function png(size, rgba) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA — Windows expects an alpha channel in an icon
  const rows = [];
  for (let y = 0; y < size; y += 1) {
    rows.push(Buffer.concat([Buffer.from([0]), rgba.subarray(y * size * 4, (y + 1) * size * 4)]));
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(rows), { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---- ICO --------------------------------------------------------------------
//
// A directory of images. Every entry here is a PNG, which Windows has accepted
// since Vista and which keeps the file small. A side of 256 is written as 0,
// because the field is one byte.

const images = SIZES.map((size) => ({ size, data: png(size, render(size)) }));

const header = Buffer.alloc(6);
header.writeUInt16LE(0, 0); // reserved
header.writeUInt16LE(1, 2); // 1 = icon
header.writeUInt16LE(images.length, 4);

const directory = Buffer.alloc(16 * images.length);
let offset = header.length + directory.length;
images.forEach((image, index) => {
  const at = index * 16;
  directory[at] = image.size === 256 ? 0 : image.size;
  directory[at + 1] = image.size === 256 ? 0 : image.size;
  directory[at + 2] = 0; // palette colours
  directory[at + 3] = 0; // reserved
  directory.writeUInt16LE(1, at + 4); // colour planes
  directory.writeUInt16LE(32, at + 6); // bits per pixel
  directory.writeUInt32LE(image.data.length, at + 8);
  directory.writeUInt32LE(offset, at + 12);
  offset += image.data.length;
});

const ico = Buffer.concat([header, directory, ...images.map((i) => i.data)]);
writeFileSync(OUT, ico);
console.log(
  `wrote ${OUT} — ${images.length} sizes (${SIZES.join(', ')}), ${(ico.length / 1024).toFixed(1)} KB`
);
