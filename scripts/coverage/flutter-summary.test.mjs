// node --test for flutter-summary.mjs (run by scripts/coverage/flutter.sh):
// the lcov parser, the Dart function scanner and the function totals it
// feeds, the coverage:ignore-* checks, and one whole run of the script on a
// tiny package. The fixtures are inline Dart and lcov text.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  A10,
  dartFunctions,
  functionTotals,
  functionTotalsFrom,
  ignoreProblems,
  namesA10,
  parseLcov,
  scanIgnores,
} from './flutter-summary.mjs';

const SCRIPT = path.join(path.dirname(fileURLToPath(import.meta.url)), 'flutter-summary.mjs');

// Every kind of declaration package:coverage lists, and the look-alikes it
// does not: commented-out code, external and abstract members, a redirecting
// factory, fields holding closures, local functions, braces in strings.
const DART = `import 'dart:async';

/* int notAFunction() => 0; */
// int alsoNot() => 0;

@pragma('vm:prefer-inline')
int topLevel(int x) => x + 1;

String get topGetter => 'x { y } \${'}'}';

set topSetter(String v) {}

external int nativeThing();

typedef Callback = void Function(int);

final handler = (int x) => x;

abstract class Shape {
  Shape(this.sides);
  Shape.square() : sides = 4;
  factory Shape.redirect() = Square;
  factory Shape.make() {
    return Square();
  }

  final int sides;

  double area();

  @override
  String toString() {
    String local() => 'local';
    return '\${local()} \${sides > 2 ? '{' : '}'}';
  }

  @override
  bool operator ==(Object other) => other is Shape && other.sides == sides;

  @override
  int get hashCode => sides;
}

class Square extends Shape {
  Square() : super(4);

  @override
  double area() => 1;
}

enum Kind { a, b }

enum Sized {
  small(1),
  big(2);

  const Sized(this.size);
  final int size;
}

extension on String {
  String shout() => toUpperCase();
}

mixin Loud {
  void speak() {}
}
`;

// [line, kind, name] for each function in DART, on the line the Dart VM
// records its entry: the first annotation, else the first token.
const EXPECTED = [
  [6, 'function', 'topLevel'],
  [9, 'getter', 'topGetter'],
  [11, 'setter', 'topSetter'],
  [20, 'constructor', 'Shape'],
  [21, 'constructor', 'Shape.square'],
  [23, 'factory', 'Shape.make'],
  [31, 'method', 'Shape.toString'],
  [37, 'operator', 'Shape.operator =='],
  [40, 'getter', 'Shape.hashCode'],
  [45, 'constructor', 'Square'],
  [47, 'method', 'Square.area'],
  [51, 'implicit constructor', 'Kind'],
  [57, 'constructor', 'Sized'],
  [62, 'method', '<extension>.shout'],
  [66, 'method', 'Loud.speak'],
];

/** One lcov record for [file] with the DA [hits] ({ line: count }). */
function lcovRecord(file, hits, extra = []) {
  const da = Object.entries(hits).map(([line, count]) => `DA:${line},${count}`);
  return [`SF:${file}`, ...da, ...extra, 'end_of_record'].join('\n');
}

const tempDirs = [];
after(() => {
  for (const dir of tempDirs) fs.rmSync(dir, { recursive: true, force: true });
});

function tempDir() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'flutter-summary-test-'));
  tempDirs.push(dir);
  return dir;
}

function writeFiles(root, files) {
  for (const [rel, text] of Object.entries(files)) {
    const file = path.join(root, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }
}

test('dartFunctions lists what package:coverage lists, on its entry line', () => {
  const found = dartFunctions(DART).map((fn) => [fn.line, fn.kind, fn.name]);

  assert.deepEqual(found, EXPECTED);
});

test('parseLcov: DA hits add up per line; BRDA, FN, FNDA and totals are kept', () => {
  const records = parseLcov([
    'TN:',
    lcovRecord('lib/a.dart', { 3: 1, 4: 0 }, [
      'DA:3,2',
      'BRDA:4,0,0,-',
      'BRDA:4,0,1,5',
      'FN:3,main',
      'FNDA:7,main',
      'LF:2',
      'LH:1',
      'BRF:2',
      'BRH:1',
    ]),
    lcovRecord('lib/b.dart', { 1: 0 }),
  ].join('\n'));

  assert.deepEqual([...records.keys()], ['lib/a.dart', 'lib/b.dart']);
  const a = records.get('lib/a.dart');
  assert.deepEqual([...a.da], [[3, 3], [4, 0]]);
  assert.deepEqual(a.brda, [
    { line: 4, block: '0', branch: '0', taken: '-' },
    { line: 4, block: '0', branch: '1', taken: '5' },
  ]);
  assert.deepEqual([...a.fn], [['main', 3]]);
  assert.deepEqual([...a.fnda], [['main', 7]]);
  assert.deepEqual(a.summary, { LF: 2, LH: 1, BRF: 2, BRH: 1 });
  assert.deepEqual([...records.get('lib/b.dart').da], [[1, 0]]);
});

test('functionTotalsFrom derives functions: a hit on the entry line covers it', () => {
  // Every function hit except two: Shape.square ran 0 times (a DA line with
  // no hits) and Loud.speak has no DA line at all.
  const hits = Object.fromEntries(EXPECTED.map(([line]) => [line, 1]));
  hits[21] = 0;
  delete hits[66];
  const [rec] = parseLcov(lcovRecord('lib/fixture.dart', hits)).values();

  const result = functionTotalsFrom(rec, DART);

  assert.equal(result.source, 'derived');
  assert.deepEqual(result.totals, [EXPECTED.length - 2, EXPECTED.length]);
  assert.deepEqual(result.missed, ['Shape.square@21', 'Loud.speak@66']);
});

test('functionTotalsFrom: no hits covers nothing; no source gives no totals', () => {
  const zero = Object.fromEntries(EXPECTED.map(([line]) => [line, 0]));
  const [rec] = parseLcov(lcovRecord('lib/fixture.dart', zero)).values();

  assert.deepEqual(functionTotalsFrom(rec, DART).totals, [0, EXPECTED.length]);
  assert.deepEqual(functionTotalsFrom(rec, null), { totals: null, missed: [], source: null });
});

test('functionTotalsFrom prefers FN/FNDA records when lcov.info has them', () => {
  const [rec] = parseLcov(lcovRecord('lib/a.dart', { 1: 1 }, [
    'FN:1,hit',
    'FN:5,miss',
    'FN:9,neverListed',
    'FNDA:3,hit',
    'FNDA:0,miss',
  ])).values();
  const [withTotals] = parseLcov(lcovRecord('lib/a.dart', {}, [
    'FN:1,hit',
    'FNDA:0,hit',
    'FNF:4',
    'FNH:3',
  ])).values();

  // The source is not read: FN records win.
  assert.deepEqual(functionTotalsFrom(rec, DART), {
    totals: [1, 3],
    missed: ['miss', 'neverListed'],
    source: 'lcov',
  });
  assert.deepEqual(functionTotalsFrom(withTotals, null).totals, [3, 4]);
});

test('functionTotals reads the source from the package, when it is there', () => {
  const pkg = tempDir();
  writeFiles(pkg, { 'lib/fixture.dart': DART });
  const hits = Object.fromEntries(EXPECTED.map(([line]) => [line, 1]));
  const [rec] = parseLcov(lcovRecord('lib/fixture.dart', hits)).values();
  const [gone] = parseLcov(lcovRecord('lib/gone.dart', { 1: 1 })).values();
  const [listed] = parseLcov(lcovRecord('lib/gone.dart', {}, ['FN:1,f', 'FNDA:1,f'])).values();

  assert.deepEqual(functionTotals(rec, pkg).totals, [EXPECTED.length, EXPECTED.length]);
  assert.equal(functionTotals(gone, pkg).totals, null);
  assert.deepEqual(functionTotals(listed, pkg).totals, [1, 1]);
});

test('namesA10: the reason must name an A10 category', () => {
  for (const category of Object.values(A10)) {
    assert.equal(namesA10(`${category}: why`), true, category);
  }
  assert.equal(namesA10('Dead: Pending Delete Decision (the old API)'), true);
  assert.equal(namesA10('dead code'), false);
  assert.equal(namesA10('hard to test'), false);
  assert.equal(namesA10(null), false);
});

test('scanIgnores and ignoreProblems: every ignore needs an A10 reason', () => {
  const pkg = tempDir();
  writeFiles(pkg, {
    'lib/a.dart': [
      'void a() {} // coverage:ignore-line dead: pending delete decision',
      'void b() {} // coverage:ignore-line hard to reach in tests',
      '// coverage:ignore-start — third-party-init: needs a real device',
      'void c() {}',
      '// coverage:ignore-end',
      'void d() {} // coverage:ignore-line',
      '// coverage:ignore-start not worth it',
      '// coverage:ignore-end',
    ].join('\n'),
    'lib/gen.dart': '// coverage:ignore-file constants only\n',
    'lib/stray.dart': '// coverage:ignore-file generated\n',
    'lib/bare.dart': '// coverage:ignore-file\n',
  });
  const files = ['lib/a.dart', 'lib/bare.dart', 'lib/gen.dart', 'lib/stray.dart'];

  const ignores = scanIgnores(pkg, files);
  const problems = ignoreProblems(ignores, (file) => file === 'lib/gen.dart' || file === 'lib/bare.dart');

  assert.deepEqual(ignores.map((i) => [i.path, i.line, i.directive, i.reason]), [
    ['lib/a.dart', 1, 'ignore-line', 'dead: pending delete decision'],
    ['lib/a.dart', 2, 'ignore-line', 'hard to reach in tests'],
    ['lib/a.dart', 3, 'ignore-start', 'third-party-init: needs a real device'],
    ['lib/a.dart', 5, 'ignore-end', null],
    ['lib/a.dart', 6, 'ignore-line', null],
    ['lib/a.dart', 7, 'ignore-start', 'not worth it'],
    ['lib/a.dart', 8, 'ignore-end', null],
    ['lib/bare.dart', 1, 'ignore-file', null],
    ['lib/gen.dart', 1, 'ignore-file', 'constants only'],
    ['lib/stray.dart', 1, 'ignore-file', 'generated'],
  ]);
  const categories = Object.values(A10).join(', ');
  assert.deepEqual(problems, [
    `coverage:ignore-line reason names no A10 category (${categories}): lib/a.dart:2`,
    'coverage:ignore-line without a reason: lib/a.dart:6',
    `coverage:ignore-start reason names no A10 category (${categories}): lib/a.dart:7`,
    'coverage:ignore-file without a reason: lib/bare.dart:1',
    'coverage:ignore-file on a file EXCLUDED does not list with an A10 category: lib/stray.dart:1',
  ]);
});

test('a whole run: the gate, per-file numbers and --enforce', () => {
  const pkg = tempDir();
  // The two files EXCLUDED lists, so no exclusion is stale.
  const base = {
    'lib/sellwild_sdk.dart': "library sellwild_sdk;\n\nexport 'src/a.dart';\n",
    'lib/src/failures/sellwild_failure_code.dart':
      "// coverage:ignore-file constants only\nabstract final class C {\n  static const String a = 'a';\n}\n",
  };
  const aSource = 'int one() => 1;\n\nint two(bool b) {\n  if (b) return 2;\n  return 0;\n}\n';
  const lcov = lcovRecord('lib/src/a.dart', { 1: 1, 3: 1, 4: 1, 5: 1 }, [
    'BRDA:4,0,0,1',
    'BRDA:4,0,1,1',
  ]);
  const run = (files, lcovText, extra = []) => {
    writeFiles(pkg, files);
    const lcovFile = path.join(pkg, 'lcov.info');
    const out = path.join(pkg, 'summary.json');
    fs.writeFileSync(lcovFile, lcovText);
    const r = spawnSync(process.execPath, [
      SCRIPT, '--lcov', lcovFile, '--pkg', pkg, '--out', out, '--tests-exit', '0', ...extra,
    ], { encoding: 'utf8' });
    return { status: r.status, stderr: r.stderr, summary: JSON.parse(fs.readFileSync(out, 'utf8')) };
  };

  const full = run({ ...base, 'lib/src/a.dart': aSource }, lcov, ['--enforce']);

  assert.equal(full.status, 0, full.stderr);
  assert.equal(full.stderr, '');
  assert.deepEqual(full.summary.gate.lines, { covered: 4, total: 4, pct: 100 });
  assert.deepEqual(full.summary.gate.branches, { covered: 2, total: 2, pct: 100 });
  assert.deepEqual(full.summary.gate.functions, { covered: 2, total: 2, pct: 100 });
  assert.equal(full.summary.gate.complete, true);
  const a = full.summary.perFile.find((f) => f.path === 'lib/src/a.dart');
  assert.equal(a.inGate, true);
  assert.deepEqual(
    full.summary.perFile.filter((f) => f.excluded).map((f) => [f.path, f.excluded]),
    [['lib/sellwild_sdk.dart', A10.entryBootstrap], ['lib/src/failures/sellwild_failure_code.dart', A10.generated]],
  );

  // two() never ran, and an ignore-line gives no A10 category: --enforce
  // fails, and says why.
  const missed = run(
    { ...base, 'lib/src/a.dart': `${aSource}// coverage:ignore-line flaky\n` },
    lcovRecord('lib/src/a.dart', { 1: 1, 3: 0, 4: 0, 5: 0 }, ['BRDA:4,0,0,0', 'BRDA:4,0,1,0']),
    ['--enforce'],
  );

  assert.equal(missed.status, 2);
  assert.deepEqual(missed.summary.gate.functions, { covered: 1, total: 2, pct: 50 });
  assert.deepEqual(missed.summary.perFile.find((f) => f.path === 'lib/src/a.dart').missedFunctions, ['two@3']);
  assert.match(missed.stderr, /gate lines 25% < 95%/);
  assert.match(missed.stderr, /gate branches 0% < 95%/);
  assert.match(missed.stderr, /gate functions 50% < 95%/);
  assert.match(missed.stderr, /coverage:ignore-line reason names no A10 category .*lib\/src\/a\.dart:7/);

  // Without --enforce the summary is still written and the run passes.
  const report = run({}, lcovRecord('lib/src/a.dart', { 1: 1, 3: 0, 4: 0, 5: 0 }));
  assert.equal(report.status, 0);
});
