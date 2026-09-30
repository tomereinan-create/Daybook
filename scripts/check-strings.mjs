import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/// Catches localized keys asked for in a form the catalog does not hold.
///
/// SwiftUI builds a `LocalizedStringKey` from the literal *including* its
/// format specifiers: `Text("field.count \(n)")` looks up `field.count %lld`,
/// not `field.count`. Get that wrong and nothing fails — no warning, no
/// crash. The key itself appears on screen, in both languages, and only
/// somebody holding the device ever finds out. Two shipped that way before
/// this existed.
///
/// The check only ever compares against keys the catalog already holds. A
/// literal the catalog has never heard of is left alone, because an SF Symbol
/// name is spelled exactly like a key and no amount of guessing from the
/// source tells them apart. That makes this quiet about things it cannot
/// know, and certain about the one thing it can.

const CATALOG = 'App/Resources/Localizable.xcstrings';
const ROOTS = ['App', 'Core', 'Widgets'];

const keys = new Set(Object.keys(JSON.parse(readFileSync(CATALOG, 'utf8')).strings));

/// "field.count %lld" is held under the base "field.count".
const withArgument = new Map();
for (const key of keys) {
  const space = key.indexOf(' ');
  if (space > 0) withArgument.set(key.slice(0, space), key);
}

function* swiftFiles(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) yield* swiftFiles(path);
    else if (entry.endsWith('.swift')) yield path;
  }
}

// The literal, and whatever follows it up to the closing quote — which is
// where an interpolation would be.
const LITERAL = /"([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)((?:[^"\\]|\\.)*)"/g;

const problems = [];
let checked = 0;

for (const root of ROOTS) {
  for (const file of swiftFiles(root)) {
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, index) => {
      if (line.trimStart().startsWith('//')) return;
      for (const match of line.matchAll(LITERAL)) {
        const base = match[1];
        const plain = keys.has(base);
        const formatted = withArgument.get(base);
        // Not a key this catalog knows in any form: not ours to judge.
        if (!plain && !formatted) continue;

        checked += 1;
        const interpolated = match[2].includes('\\(');
        const where = `${file}:${index + 1}`;

        if (interpolated && !formatted) {
          problems.push(
            `${where}\n    "${base}" is interpolated here, but the catalog holds it with no ` +
              `format specifier.\n    The lookup misses and the key itself is drawn. Rename the ` +
              `catalog entry to "${base} %@" or "${base} %lld".`
          );
        } else if (!interpolated && !plain) {
          problems.push(
            `${where}\n    "${base}" is used with nothing interpolated, but the catalog only ` +
              `holds "${formatted}".\n    The lookup misses and the key itself is drawn.`
          );
        }
      }
    });
  }
}

console.log(`${keys.size} keys in the catalog; ${checked} uses of them checked in Swift.`);

if (problems.length) {
  console.error(`\n${problems.length} key(s) asked for in a form the catalog does not hold:\n`);
  for (const problem of problems) console.error(`  ${problem}\n`);
  process.exit(1);
}
console.log('Every one is asked for in the form the catalog holds it.');
