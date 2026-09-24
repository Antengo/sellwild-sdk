#!/usr/bin/env node
// Summarizes an iOS coverage run into coverage-summary/ios.json (contract
// amendment A10).
//
// Inputs, all written by scripts/coverage/ios.sh:
//   --xccov    `xccov view --report --json`: per-file executable/covered lines
//   --archive  `xccov view --archive --json`: per-line counts (missed lines)
//   --llvm     `llvm-cov export -summary-only`: per-file regions and functions
//   --results  `xcresulttool get test-results summary`: test counts (optional)
//
// Swift emits no llvm-cov branch data, so `branches` is null and `regions`
// stands in for branches in the gate. Lines come from xccov (what Xcode
// shows); regions and functions come from llvm-cov over the same profile.
//
// Honesty checks, reported in the JSON and on stderr:
//   - Swift files under ios/Sources/SellwildSDK missing from the coverage data
//     ("unmeasured"). Either cover them or add them to EXCLUDED with a reason.
//   - a file whose xccov and llvm-cov line totals disagree.
//   - a file xccov measured but llvm-cov did not. Its regions and functions
//     count as 0/0, so they are left out of those totals, not counted as covered.
//
// Usage:
//   node ios-summary.mjs --xccov <json> --archive <json> --llvm <json> --root <repo> --out <json>
//     [--results <json>] [--command "<cmd>"]... [--tests-exit <n>] [--contracts <status>]
//     [--network <status>] [--enforce]
// --enforce exits 2 when the gate is under 95% lines, regions or functions, or
// a check above fails. Without it the script exits 0 once the summary is written.

import fs from 'node:fs';
import path from 'node:path';

const TARGET_PCT = 95;
const TARGET_NAME = 'SellwildSDK';
const SOURCE_ROOT = 'ios/Sources/SellwildSDK';

// Phase 1 (phase1/sdk-ios.json) classified the first nine files pure or mostly
// pure. Failures/ holds logFailure (A2); Core/ holds pure code extracted from
// the UIKit, Prebid and GMA glue.
const GATE_INCLUDE = [
  `${SOURCE_ROOT}/SellwildAdStack.swift`,
  `${SOURCE_ROOT}/SellwildGpid.swift`,
  `${SOURCE_ROOT}/SellwildSafeURL.swift`,
  `${SOURCE_ROOT}/SellwildLocalizedListings.swift`,
  `${SOURCE_ROOT}/SellwildGeo.swift`,
  `${SOURCE_ROOT}/SellwildConfig.swift`,
  `${SOURCE_ROOT}/SellwildAdSizes.swift`,
  `${SOURCE_ROOT}/SellwildNative.swift`,
  `${SOURCE_ROOT}/SellwildVideo.swift`,
  `${SOURCE_ROOT}/Failures/**`,
  `${SOURCE_ROOT}/Core/**`,
];
const WHOLE_INCLUDE = [`${SOURCE_ROOT}/**`];

// A10 allows exclusions only for type-only files, generated output, tiny entry
// bootstraps, third-party SDK init that needs a device or network, and dead
// code pending a delete decision. Each entry: { path: '<glob>', reason: '...' }.
// Files the build generates outside ios/Sources/SellwildSDK are added below.
const EXCLUDED = [];

// Not part of the SellwildSDK target, so never in `whole`. Listed so the
// report says what it does not measure. These are not A10 exclusions.
const OUTSIDE_TARGET = [
  {
    path: 'react-native/ios/**',
    reason: 'React Native bridge. It imports React, so no SwiftPM test target compiles it. Pure mapping code must move into ios/Sources/SellwildSDK to be measured.',
  },
  {
    path: 'ios/Tests/**',
    reason: 'Test code (SellwildSDKTests, and DocsVerifyTests, which only compile-checks docs snippets).',
  },
  {
    path: 'SourcePackages/**',
    reason: 'Third-party packages checked out in derived data (SellwildPrebidSDK fork, GoogleMobileAds). Not our code.',
  },
];

const NOTES = [
  'branches is null: Swift emits no llvm-cov branch data. regions (llvm-cov code regions) stand in for branches in the gate.',
  'lines come from xccov; regions and functions come from llvm-cov export over the same Coverage.profdata.',
  'SellwildSDKTests run with NetworkBlocker (ios/Tests/SellwildSDKTests/Support). It fails every request made through URLSession.shared, Data(contentsOf:), and sessions built from the .default or .ephemeral configuration. It does not see WKWebView loads, background session configurations, sessions whose protocolClasses a test replaces, or Network.framework and socket traffic. DocsVerifyTests has no blocker; it only compile-checks docs snippets and runs one empty test.',
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
      case '--xccov': args.xccov = value(); break;
      case '--archive': args.archive = value(); break;
      case '--llvm': args.llvm = value(); break;
      case '--results': args.results = value(); break;
      case '--root': args.root = value(); break;
      case '--out': args.out = value(); break;
      case '--command': args.commands.push(value()); break;
      case '--tests-exit': args.testsExit = Number(value()); break;
      case '--contracts': args.contracts = value(); break;
      case '--network': args.network = value(); break;
      case '--enforce': args.enforce = true; break;
      default: throw new Error(`unknown argument ${flag}`);
    }
  }
  for (const required of ['xccov', 'archive', 'llvm', 'root', 'out']) {
    if (!args[required]) throw new Error(`--${required} is required`);
  }
  return args;
}

const readJSON = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));

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

function listSwiftFiles(root, dir) {
  const base = path.join(root, dir);
  if (!fs.existsSync(base)) return [];
  const out = [];
  for (const entry of fs.readdirSync(base, { withFileTypes: true, recursive: true })) {
    if (entry.isFile() && entry.name.endsWith('.swift')) {
      out.push(path.relative(root, path.join(entry.parentPath ?? entry.path, entry.name)).split(path.sep).join('/'));
    }
  }
  return out.sort();
}

// Compare real paths: the root may be reached through a symlink. A file the
// report names that is gone (e.g. a generated source) keeps its path as given,
// so it is still reported.
function relativeTo(root) {
  const realRoot = fs.realpathSync(root);
  return (file) => {
    const real = fs.existsSync(file) ? fs.realpathSync(file) : file;
    return path.relative(realRoot, real).split(path.sep).join('/');
  };
}

function aggregate(entries, key) {
  const covered = entries.reduce((sum, e) => sum + e[key][0], 0);
  const total = entries.reduce((sum, e) => sum + e[key][1], 0);
  return counts(covered, total);
}

function summarize(entries) {
  return {
    lines: aggregate(entries, 'lines'),
    branches: null,
    regions: aggregate(entries, 'regions'),
    functions: aggregate(entries, 'functions'),
  };
}

function testResults(file, testsExit) {
  if (!file && testsExit === undefined) return null;
  const out = { exitCode: testsExit ?? null, passed: testsExit === undefined ? null : testsExit === 0 };
  if (file && fs.existsSync(file)) {
    const r = readJSON(file);
    const device = r.devicesAndConfigurations?.[0]?.device;
    Object.assign(out, {
      result: r.result ?? null,
      passedTests: r.passedTests ?? null,
      failedTests: r.failedTests ?? null,
      skippedTests: r.skippedTests ?? null,
      expectedFailures: r.expectedFailures ?? null,
      device: device ? `${device.deviceName} (${device.platform} ${device.osVersion})` : null,
    });
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root);
  const rel = relativeTo(root);

  const report = readJSON(args.xccov);
  const target = (report.targets ?? []).find((t) => t.name === TARGET_NAME);
  if (!target) throw new Error(`${args.xccov} has no ${TARGET_NAME} target`);

  const archive = readJSON(args.archive);
  const missedByFile = new Map();
  for (const [file, lines] of Object.entries(archive)) {
    const missed = lines.filter((l) => l.isExecutable && l.executionCount === 0).map((l) => l.line);
    missedByFile.set(rel(file), missed.sort((a, b) => a - b));
  }

  const llvm = readJSON(args.llvm);
  const llvmByFile = new Map();
  for (const f of llvm.data?.[0]?.files ?? []) llvmByFile.set(rel(f.filename), f.summary);

  const targetFiles = new Map(target.files.map((f) => [rel(f.path), f]));
  const generated = [...targetFiles.keys()]
    .filter((file) => !matchesAny(file, WHOLE_INCLUDE))
    .map((file) => ({ path: file, reason: `generated build output (outside ${SOURCE_ROOT})` }));
  const excluded = [...EXCLUDED, ...generated];
  const isExcluded = (file) => matchesAny(file, excluded.map((e) => e.path));

  const mismatches = [];
  const noLlvm = [];
  const entries = [...targetFiles]
    .filter(([file]) => matchesAny(file, WHOLE_INCLUDE) && !isExcluded(file))
    .map(([file, x]) => {
      const l = llvmByFile.get(file);
      if (!l) noLlvm.push(file);
      if (l && l.lines.count !== x.executableLines) {
        mismatches.push(`${file}: xccov ${x.executableLines} lines, llvm-cov ${l.lines.count}`);
      }
      return {
        path: file,
        lines: [x.coveredLines, x.executableLines],
        regions: l ? [l.regions.covered, l.regions.count] : [0, 0],
        functions: l ? [l.functions.covered, l.functions.count] : [0, 0],
        missed: missedByFile.get(file) ?? [],
        inGate: matchesAny(file, GATE_INCLUDE),
      };
    })
    .sort((a, b) => a.path.localeCompare(b.path));

  const measured = new Set(entries.map((e) => e.path));
  const unmeasured = listSwiftFiles(root, SOURCE_ROOT).filter((file) => !measured.has(file) && !isExcluded(file));
  const gateUnmeasured = unmeasured.filter((file) => matchesAny(file, GATE_INCLUDE));

  const pctOf = (pair) => counts(pair[0], pair[1]).pct;
  const summary = {
    platform: 'ios',
    generatedAt: new Date().toISOString(),
    tool: 'xccov+llvm-cov',
    commands: args.commands,
    gate: { include: GATE_INCLUDE, ...summarize(entries.filter((e) => e.inGate)), unmeasured: gateUnmeasured },
    whole: { include: WHOLE_INCLUDE, target: TARGET_NAME, ...summarize(entries), unmeasured },
    excluded,
    outsideTarget: OUTSIDE_TARGET,
    perFile: [
      ...entries.map((e) => ({
        path: e.path,
        lines: pctOf(e.lines),
        branches: null,
        regions: pctOf(e.regions),
        functions: pctOf(e.functions),
        inGate: e.inGate,
        linesCovered: e.lines[0],
        linesTotal: e.lines[1],
        missedLines: compressLines(e.missed),
      })),
      ...unmeasured.map((file) => ({
        path: file,
        lines: null,
        branches: null,
        regions: null,
        functions: null,
        inGate: matchesAny(file, GATE_INCLUDE),
        measured: false,
      })),
    ],
    tests: testResults(args.results, args.testsExit),
    contracts: args.contracts ?? null,
    networkLeftovers: args.network ?? null,
    notes: [
      ...NOTES,
      ...mismatches.map((m) => `line totals differ: ${m}`),
      ...noLlvm.map((file) => `no llvm-cov data for ${file}: its regions and functions are not in the totals`),
    ],
  };

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, `${JSON.stringify(summary, null, 2)}\n`);

  const problems = [];
  for (const file of unmeasured) problems.push(`not in the coverage data (cover it or exclude it with a reason): ${file}`);
  for (const m of mismatches) problems.push(`xccov and llvm-cov line totals differ: ${m}`);
  for (const file of noLlvm) problems.push(`no llvm-cov data (regions and functions not counted): ${file}`);
  const below = (metric) => metric.total > 0 && (metric.covered / metric.total) * 100 < TARGET_PCT;
  for (const key of ['lines', 'regions', 'functions']) {
    if (below(summary.gate[key])) problems.push(`gate ${key} ${summary.gate[key].pct}% < ${TARGET_PCT}%`);
  }

  const fmt = (m) => (m.total === 0 ? 'n/a' : `${m.covered}/${m.total} (${m.pct}%)`);
  const line = (label, s) =>
    `  ${label} lines ${fmt(s.lines)}  regions ${fmt(s.regions)}  functions ${fmt(s.functions)}\n`;
  const shown = path.relative(root, path.resolve(args.out));
  process.stdout.write(`ios coverage -> ${shown.startsWith('..') ? path.resolve(args.out) : shown}\n`
    + line('gate ', summary.gate) + line('whole', summary.whole));
  for (const p of problems) process.stderr.write(`  ! ${p}\n`);
  if (args.enforce && problems.length > 0) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  process.stderr.write(`ios-summary: ${error.message}\n`);
  process.exitCode = 1;
}
