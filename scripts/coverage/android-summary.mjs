#!/usr/bin/env node
// Summarizes an Android coverage run into coverage-summary/android.json
// (contract amendment A10).
//
// Inputs, all written by scripts/coverage/android.sh:
//   --xml      Kover's JaCoCo-format XML report (android/build/reports/kover/reportDebug.xml)
//   --results  the JUnit XML results dir of testDebugUnitTest (test counts, optional)
//
// Lines and branches are each <sourcefile>'s own LINE and BRANCH counters, the
// numbers Kover's HTML report shows. (Kover counts a line once per class that
// has code on it, so a lambda's line can count twice; the <line> rows are only
// used to list missed lines.) Kover writes no METHOD counter per source file,
// so functions are the sum of the METHOD counters of the classes compiled from
// that file. Kover already drops AGP-generated classes
// (androidGeneratedClasses() in android/build.gradle.kts), so no other build
// output reaches the XML.
//
// Honesty checks, reported in the JSON and on stderr:
//   - Kotlin/Java files under android/src/main missing from the report
//     ("unmeasured"). Either cover them or add them to EXCLUDED with a reason.
//   - a report source file that matches no file under android/src/main.
//   - per-file sums that disagree with the report's own totals.
//
// Usage:
//   node android-summary.mjs --xml <reportDebug.xml> --root <repo> --out <json>
//     [--results <dir>] [--command "<cmd>"]... [--tests-exit <n>] [--contracts <status>] [--enforce]
// --enforce exits 2 when the gate is under 95% lines, branches or functions,
// or a check above fails. Without it the script exits 0 once the summary is written.

import fs from 'node:fs';
import path from 'node:path';

const TARGET_PCT = 95;
const MODULE = 'android';
const SOURCE_DIRS = [`${MODULE}/src/main/kotlin`, `${MODULE}/src/main/java`];
const SOURCE_ROOT = `${MODULE}/src/main/kotlin/com/sellwild/sdk`;

// Phase 1 (phase1/sdk-android.json) classified the first nine files pure or
// mostly pure. It also classified RnGeo.kt and RnPrebidServer.kt mostly pure,
// but they sit in react-native/android, which no JVM test builds (OUTSIDE_MODULE
// names them). failures/ holds logFailure (A2); core/ holds pure code extracted
// from the View, WebView, GMA and Prebid glue.
const GATE_INCLUDE = [
  `${SOURCE_ROOT}/SellwildConfig.kt`,
  `${SOURCE_ROOT}/SellwildLocalizedListings.kt`,
  `${SOURCE_ROOT}/SellwildAdStack.kt`,
  `${SOURCE_ROOT}/SellwildGpid.kt`,
  `${SOURCE_ROOT}/SellwildNative.kt`,
  `${SOURCE_ROOT}/SellwildAdSizes.kt`,
  `${SOURCE_ROOT}/SellwildGeo.kt`,
  `${SOURCE_ROOT}/SellwildSafeUrl.kt`,
  `${SOURCE_ROOT}/SellwildVideo.kt`,
  `${SOURCE_ROOT}/failures/**`,
  `${SOURCE_ROOT}/core/**`,
];
const WHOLE_INCLUDE = [`${MODULE}/src/main/**`];

// A10 allows exclusions only for type-only files, generated output, tiny entry
// bootstraps, third-party SDK init that needs a device or network, and dead
// code pending a delete decision. Each entry: { path: '<glob>', reason: '...' }.
const EXCLUDED = [
  {
    path: `${MODULE}/build/generated/**`,
    reason: 'AGP-generated classes (R, BuildConfig, Manifest, data binding). Kover drops them before writing the XML (androidGeneratedClasses() in android/build.gradle.kts). This library compiles none into its own classes today.',
  },
];

// Not part of the android module, so never in `whole`. Listed so the report
// says what it does not measure. These are not A10 exclusions.
const OUTSIDE_MODULE = [
  {
    path: 'react-native/android/**',
    reason: 'React Native bridge. It has no Gradle wrapper or test source set and compiles against the RN host, so no JVM test measures it. Phase 1 classified two of its files mostly pure, and so gate candidates, but neither is measured: react-native/android/src/main/java/com/sellwild/rnsdk/RnGeo.kt and react-native/android/src/main/java/com/sellwild/rnsdk/RnPrebidServer.kt. Pure mapping code must move into android/src/main to be measured.',
  },
  {
    path: `${MODULE}/src/test/**`,
    reason: 'Test code, including the harness in src/test/kotlin/com/sellwild/sdk/support.',
  },
];

const NOTES = [
  'Coverage engine: Kover 0.9.1 (IntelliJ coverage agent), JaCoCo-format XML. A line counts as covered when any of its instructions ran.',
  'branches: Kover counts every `?.`, `?:`, `when` arm and short-circuit operand as a branch, so null-heavy Kotlin reaches 95% branches later than 95% lines.',
  'functions: JVM methods from Kover METHOD counters, including compiler-generated ones (default-argument bridges, data class members, lambdas).',
  'regions is null: Kover has no region data.',
  'Unit tests run on the JUnit Platform (vintage engine) with support/NetworkBlock.kt installed JVM-wide before the first test, and the test task fails when any test opened a connection it did not expect (support/NetworkBlockAuditListener.kt), so no covered path reached the network. Requests a test needs are answered in-process by support/HttpStub.kt. Robolectric runs offline from a Gradle-resolved android-all jar.',
];

function parseArgs(argv) {
  const args = { commands: [], enforce: false };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    const value = () => {
      if (i + 1 >= argv.length) throw new Error(`${flag} needs a value`);
      return argv[++i];
    };
    switch (flag) {
      case '--xml': args.xml = value(); break;
      case '--root': args.root = value(); break;
      case '--out': args.out = value(); break;
      case '--results': args.results = value(); break;
      case '--command': args.commands.push(value()); break;
      case '--tests-exit': args.testsExit = Number(value()); break;
      case '--contracts': args.contracts = value(); break;
      case '--enforce': args.enforce = true; break;
      default: throw new Error(`unknown argument ${flag}`);
    }
  }
  for (const required of ['xml', 'root', 'out']) {
    if (!args[required]) throw new Error(`--${required} is required`);
  }
  return args;
}

const unescapeXml = (s) =>
  s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

function attributes(text) {
  const out = {};
  for (const m of text.matchAll(/([\w:-]+)="([^"]*)"/g)) out[m[1]] = unescapeXml(m[2]);
  return out;
}

// Kover's XML is flat and regular (report > package > class > method, and
// package > sourcefile > line), so a tag scanner with a parent stack is enough.
function parseKoverXml(text) {
  const report = { counters: {}, files: new Map(), classMethods: new Map() };
  const stack = [];
  let pkg = null;
  for (const m of text.matchAll(/<(\/?)([A-Za-z]+)((?:\s+[\w:-]+="[^"]*")*)\s*(\/?)>/g)) {
    const [, closing, tag, attrText, selfClosing] = m;
    if (closing) {
      stack.pop();
      if (tag === 'package') pkg = null;
      continue;
    }
    const attrs = attributes(attrText);
    const parent = stack[stack.length - 1] ?? null;
    if (tag === 'package') pkg = attrs.name;
    if (tag === 'sourcefile') {
      const key = `${pkg}/${attrs.name}`;
      report.files.set(key, { key, lines: [], counters: {} });
    }
    if (tag === 'line' && parent?.tag === 'sourcefile') {
      report.files.get(parent.key).lines.push({
        nr: Number(attrs.nr), mi: Number(attrs.mi), ci: Number(attrs.ci), mb: Number(attrs.mb), cb: Number(attrs.cb),
      });
    }
    if (tag === 'counter' && parent) {
      const counter = { missed: Number(attrs.missed), covered: Number(attrs.covered) };
      if (parent.tag === 'report') report.counters[attrs.type] = counter;
      if (parent.tag === 'sourcefile') report.files.get(parent.key).counters[attrs.type] = counter;
      if (parent.tag === 'class' && attrs.type === 'METHOD') {
        const prev = report.classMethods.get(parent.key) ?? { missed: 0, covered: 0 };
        report.classMethods.set(parent.key, { missed: prev.missed + counter.missed, covered: prev.covered + counter.covered });
      }
    }
    if (!selfClosing) {
      const key = tag === 'sourcefile' ? `${pkg}/${attrs.name}`
        : tag === 'class' ? `${pkg}/${attrs.sourcefilename ?? ''}`
          : null;
      stack.push({ tag, key });
    }
  }
  return report;
}

function counts(covered, total) {
  return { covered, total, pct: total === 0 ? null : Math.round((covered / total) * 10000) / 100 };
}

// "3,7-9,12" from a sorted list of line numbers.
function compressLines(lines) {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    let j = i;
    while (j + 1 < lines.length && lines[j + 1] === lines[j] + 1) j++;
    out.push(i === j ? `${lines[i]}` : `${lines[i]}-${lines[j]}`);
    i = j;
  }
  return out.join(',');
}

function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      re += '.*';
      i++;
      if (glob[i + 1] === '/') i++;
    } else if (c === '*') {
      re += '[^/]*';
    } else {
      re += c.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
    }
  }
  return new RegExp(`^${re}$`);
}

const matchesAny = (file, globs) => globs.some((g) => globToRegExp(g).test(file));

// Maps "<package path>/<file name>" (the report's key) to the repo-relative
// source path. Kotlin allows a file's package to differ from its directory, so
// the key comes from the `package` line, not the location.
function indexSources(root) {
  const index = new Map();
  const all = [];
  for (const dir of SOURCE_DIRS) {
    const abs = path.join(root, dir);
    if (!fs.existsSync(abs)) continue;
    for (const entry of fs.readdirSync(abs, { withFileTypes: true, recursive: true })) {
      if (!entry.isFile() || !/\.(kt|java)$/.test(entry.name)) continue;
      const file = path.join(entry.parentPath ?? entry.path, entry.name);
      const rel = path.relative(root, file).split(path.sep).join('/');
      const pkg = /^\s*package\s+([\w.]+)/m.exec(fs.readFileSync(file, 'utf8'))?.[1] ?? '';
      const key = `${pkg.replace(/\./g, '/')}/${entry.name}`.replace(/^\//, '');
      all.push(rel);
      index.set(key, [...(index.get(key) ?? []), rel]);
    }
  }
  return { index, all: all.sort() };
}

function fileTotals(file, methods) {
  const of = (c) => (c ? counts(c.covered, c.covered + c.missed) : counts(0, 0));
  return { lines: of(file.counters.LINE), branches: of(file.counters.BRANCH), functions: of(methods) };
}

function aggregate(entries, key) {
  const covered = entries.reduce((sum, e) => sum + e.totals[key].covered, 0);
  const total = entries.reduce((sum, e) => sum + e.totals[key].total, 0);
  return counts(covered, total);
}

function summarize(entries) {
  return {
    lines: aggregate(entries, 'lines'),
    branches: aggregate(entries, 'branches'),
    regions: null,
    functions: aggregate(entries, 'functions'),
  };
}

// Totals from the JUnit XML files Gradle writes per test class.
function readTestResults(dir) {
  if (!dir || !fs.existsSync(dir)) return null;
  const totals = { tests: 0, failures: 0, errors: 0, skipped: 0, classes: 0 };
  for (const name of fs.readdirSync(dir)) {
    if (!name.startsWith('TEST-') || !name.endsWith('.xml')) continue;
    const suite = /<testsuite\b([^>]*)>/.exec(fs.readFileSync(path.join(dir, name), 'utf8'));
    if (!suite) continue;
    const a = attributes(suite[1]);
    totals.classes += 1;
    for (const k of ['tests', 'failures', 'errors', 'skipped']) totals[k] += Number(a[k] ?? 0);
  }
  return totals;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root);
  const report = parseKoverXml(fs.readFileSync(args.xml, 'utf8'));
  if (report.files.size === 0) throw new Error(`${args.xml} has no <sourcefile> entries`);

  const { index, all: sourceFiles } = indexSources(root);
  const problems = [];
  const isExcluded = (file) => matchesAny(file, EXCLUDED.map((e) => e.path));

  const entries = [];
  for (const file of report.files.values()) {
    const matches = index.get(file.key) ?? [];
    if (matches.length !== 1) {
      problems.push(matches.length === 0
        ? `report file ${file.key} matches no source under ${SOURCE_DIRS.join(' or ')}`
        : `report file ${file.key} matches several sources: ${matches.join(', ')}`);
    }
    const rel = matches[0] ?? `${SOURCE_DIRS[0]}/${file.key}`;
    entries.push({
      path: rel,
      totals: fileTotals(file, report.classMethods.get(file.key)),
      missed: file.lines.filter((l) => l.mi > 0 && l.ci === 0).map((l) => l.nr).sort((a, b) => a - b),
      missedBranch: file.lines.filter((l) => l.mb > 0).map((l) => l.nr).sort((a, b) => a - b),
      inGate: matchesAny(rel, GATE_INCLUDE) && !isExcluded(rel),
      inWhole: matchesAny(rel, WHOLE_INCLUDE) && !isExcluded(rel),
    });
  }
  entries.sort((a, b) => a.path.localeCompare(b.path));

  const measured = new Set(entries.map((e) => e.path));
  const unmeasured = sourceFiles.filter((file) => !measured.has(file) && !isExcluded(file));
  const gateUnmeasured = unmeasured.filter((file) => matchesAny(file, GATE_INCLUDE));
  const whole = summarize(entries.filter((e) => e.inWhole));

  // The per-file sums must reproduce Kover's own report totals.
  for (const [type, key] of [['LINE', 'lines'], ['BRANCH', 'branches'], ['METHOD', 'functions']]) {
    const c = report.counters[type];
    if (c && (c.covered !== whole[key].covered || c.covered + c.missed !== whole[key].total)) {
      problems.push(`whole ${key} ${whole[key].covered}/${whole[key].total} != report ${type} ${c.covered}/${c.covered + c.missed}`);
    }
  }

  const testResults = readTestResults(args.results);
  const summary = {
    platform: 'android',
    generatedAt: new Date().toISOString(),
    tool: 'kover 0.9.1 (IntelliJ coverage agent, JaCoCo-format XML) over testDebugUnitTest',
    commands: args.commands,
    gate: { include: GATE_INCLUDE, ...summarize(entries.filter((e) => e.inGate)), unmeasured: gateUnmeasured },
    whole: { include: WHOLE_INCLUDE, ...whole, unmeasured },
    excluded: EXCLUDED,
    outsideModule: OUTSIDE_MODULE,
    perFile: [
      ...entries.map((e) => ({
        path: e.path,
        lines: e.totals.lines.pct,
        branches: e.totals.branches.pct,
        functions: e.totals.functions.pct,
        inGate: e.inGate,
        linesCovered: e.totals.lines.covered,
        linesTotal: e.totals.lines.total,
        branchesCovered: e.totals.branches.covered,
        branchesTotal: e.totals.branches.total,
        missedLines: compressLines(e.missed),
        missedBranchLines: compressLines(e.missedBranch),
      })),
      ...unmeasured.map((file) => ({
        path: file,
        lines: null,
        branches: null,
        functions: null,
        inGate: matchesAny(file, GATE_INCLUDE),
        measured: false,
      })),
    ],
    tests: args.testsExit === undefined && !testResults
      ? null
      : {
        exitCode: args.testsExit ?? null,
        passed: args.testsExit === undefined ? null : args.testsExit === 0,
        ...(testResults ?? {}),
      },
    contracts: args.contracts ?? null,
    notes: NOTES,
  };

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, `${JSON.stringify(summary, null, 2)}\n`);

  for (const file of unmeasured) problems.push(`not in the Kover report (cover it or exclude it with a reason): ${file}`);
  const below = (metric) => metric.total > 0 && (metric.covered / metric.total) * 100 < TARGET_PCT;
  for (const key of ['lines', 'branches', 'functions']) {
    if (below(summary.gate[key])) problems.push(`gate ${key} ${summary.gate[key].pct}% < ${TARGET_PCT}%`);
  }

  const fmt = (m) => (m.total === 0 ? 'n/a' : `${m.covered}/${m.total} (${m.pct}%)`);
  const tests = testResults
    ? `  tests ${testResults.tests} in ${testResults.classes} classes, ${testResults.failures} failed, ${testResults.errors} errors, ${testResults.skipped} skipped\n`
    : '';
  process.stdout.write(
    `android coverage -> ${args.out}\n` +
    `  gate  lines ${fmt(summary.gate.lines)}  branches ${fmt(summary.gate.branches)}  functions ${fmt(summary.gate.functions)}\n` +
    `  whole lines ${fmt(summary.whole.lines)}  branches ${fmt(summary.whole.branches)}  functions ${fmt(summary.whole.functions)}\n` +
    tests,
  );
  for (const p of problems) process.stderr.write(`  ! ${p}\n`);
  if (args.enforce && problems.length > 0) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  process.stderr.write(`android-summary: ${error.message}\n`);
  process.exitCode = 1;
}
