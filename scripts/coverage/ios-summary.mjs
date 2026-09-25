#!/usr/bin/env node
// Summarizes an iOS coverage run into coverage-summary/ios.json (contract
// amendment A10).
//
// Inputs, all written by scripts/coverage/ios.sh:
//   --xccov    `xccov view --report --json`: the target's files (and llvm-cov's
//              line totals, cross-checked below)
//   --archive  `xccov view --archive --json`: per-line counts, which give the
//              line numbers (and the missed lines)
//   --llvm     `llvm-cov export` (full, not -summary-only): per-file summaries
//              and the function records with their regions
//   --results  `xcresulttool get test-results summary`: test counts (optional)
//
// Swift emits no llvm-cov branch data, so `branches` is null and `regions`
// stands in for branches in the gate. Lines are source lines from the xccov
// archive (what Xcode's editor shows, the same as llvm-cov's per-line view).
// llvm-cov's file summary, and xccov's report, count a line once for every
// function that spans it, so a line inside a closure counts twice there; the
// per-line numbers count it once, and let range comments leave lines out.
// Regions and functions come from llvm-cov over the same profile,
// counted from the function records the way llvm-cov counts them (records
// that start at the same place are one function; a group has the most
// regions and the most covered regions of its records).
//
// Swift has no coverage pragma, so A10 line ranges are marked in the source
// with a pair of comments (see RANGE_KINDS):
//
//     // sellwild-coverage:exclude-begin(<kind>) <reason>
//     ...
//     // sellwild-coverage:exclude-end
//
// Lines, code regions and functions that start between the two comments are
// left out of `gate` and listed in `excluded` with the reason. `whole` keeps
// them, and keeps the files in EXCLUDED, so gate = whole minus exclusions
// (A10) and the gap between the two shows how much was left out.
//
// Honesty checks, reported in the JSON and on stderr:
//   - Swift files under ios/Sources/SellwildSDK missing from the coverage data
//     ("unmeasured"). Either cover them or add them to EXCLUDED with a reason.
//   - a file whose xccov and llvm-cov line totals disagree.
//   - a file xccov measured but llvm-cov did not. Its regions and functions
//     count as 0/0, so they are left out of those totals, not counted as covered.
//   - a file whose function records do not add up to llvm-cov's own summary.
//   - a malformed range comment: an unknown kind, no reason, a begin without
//     an end (or the reverse), or a `dead` range without the A10 reason.
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
// the UIKit, Prebid and GMA glue. Phase 3 (sdk-ios-logic) added the logic files
// it brought to 95%: the API client and remote config shells, eids, house ads,
// GrowthCode and the audio guard, each with its I/O behind an injected seam.
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
  `${SOURCE_ROOT}/SellwildAPI.swift`,
  `${SOURCE_ROOT}/SellwildRemoteConfig.swift`,
  `${SOURCE_ROOT}/SellwildEids.swift`,
  `${SOURCE_ROOT}/SellwildHouseAd.swift`,
  `${SOURCE_ROOT}/SellwildGrowthCode.swift`,
  `${SOURCE_ROOT}/SellwildAdAudioGuard.swift`,
  // Phase 3 (sdk-ios-views): the view shells. GMA, Prebid, WKWebView, timers,
  // images and URL opening sit behind injected environments, so the shells run
  // in XCTest with fakes; their decisions moved into Core/.
  `${SOURCE_ROOT}/SellwildAdView.swift`,
  `${SOURCE_ROOT}/SellwildPrebidMobile.swift`,
  `${SOURCE_ROOT}/SellwildNativeAdView.swift`,
  `${SOURCE_ROOT}/SellwildHouseAdView.swift`,
  `${SOURCE_ROOT}/SellwildFeedView.swift`,
  `${SOURCE_ROOT}/SellwildWidgetView.swift`,
  `${SOURCE_ROOT}/SellwildSwiftUI.swift`,
  `${SOURCE_ROOT}/Failures/**`,
  `${SOURCE_ROOT}/Core/**`,
];
const WHOLE_INCLUDE = [`${SOURCE_ROOT}/**`];

// A10 allows exclusions only for type-only files, generated output, tiny entry
// bootstraps, third-party SDK init that needs a device or network, and dead
// code pending a delete decision. Each entry: { path: '<glob>', reason: '...' }.
// Files the build generates outside ios/Sources/SellwildSDK are added below.
const EXCLUDED = [
  {
    path: `${SOURCE_ROOT}/Failures/SellwildFailureCode.swift`,
    reason: 'type-only and generated: a String enum of registry raw values, written by contracts/scripts/gen-codes.mjs from contracts/failure-codes.json. No executable regions; SellwildFailureCodeTests checks it against the registry.',
  },
];

// The A10 classes a range comment may name, with what each one means. Only
// these are allowed; `dead` needs the reason A10 prescribes.
const RANGE_KINDS = {
  'third-party-init': 'third-party SDK init that needs a device or the network (A10)',
  'fetch-demand': 'a Prebid fetchDemand network call and its closure (A10)',
  preview: 'a SwiftUI preview (A10)',
  'crash-guard': 'a fatalError crash guard: running it ends the test process (A10)',
  dead: 'dead code (A10)',
};
const DEAD_REASON = 'dead: pending delete decision';
const RANGE_BEGIN = /\/\/\s*sellwild-coverage:exclude-begin\(([^)]*)\)(.*)$/;
const RANGE_END = /\/\/\s*sellwild-coverage:exclude-end\b/;

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
  'lines are source lines from the xccov archive (llvm-cov per-line data); llvm-cov and xccov report totals count a line once per function that spans it (a closure line twice), so they are larger. regions and functions come from llvm-cov export over the same Coverage.profdata, counted from its function records as llvm-cov counts them.',
  'A10 line ranges are marked in the Swift source with `// sellwild-coverage:exclude-begin(<kind>) <reason>` ... `// sellwild-coverage:exclude-end`. Lines, regions and functions starting inside are left out of gate, not whole; each range is listed in excluded as <file>:<first>-<last> with its kind and reason.',
  'gate = whole minus the A10 exclusions: whole counts every file under ios/Sources/SellwildSDK in the target, the EXCLUDED files and the range lines included. perFile numbers are the gated part of each file; a file with excluded lines also carries its whole numbers, and an EXCLUDED file (inGate false) carries only its whole numbers.',
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

function aggregate(parts, key) {
  const covered = parts.reduce((sum, p) => sum + p[key][0], 0);
  const total = parts.reduce((sum, p) => sum + p[key][1], 0);
  return counts(covered, total);
}

// Totals of one part ('gate' or 'whole') of each entry.
function summarize(entries, part) {
  const parts = entries.map((e) => e[part]);
  return {
    lines: aggregate(parts, 'lines'),
    branches: null,
    regions: aggregate(parts, 'regions'),
    functions: aggregate(parts, 'functions'),
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

// The A10 range comments in one source file: [{ start, end, kind, reason }]
// (start and end are the first and last line between the two comments), and
// what is wrong with any of them.
function sourceRanges(root, file) {
  const ranges = [];
  const problems = [];
  const full = path.join(root, file);
  if (!fs.existsSync(full)) return { ranges, problems };
  const lines = fs.readFileSync(full, 'utf8').split('\n');
  let open = null;
  lines.forEach((text, index) => {
    const lineNo = index + 1;
    const begin = RANGE_BEGIN.exec(text);
    if (begin) {
      const kind = begin[1].trim();
      const reason = begin[2].trim();
      if (open) problems.push(`${file}:${lineNo}: exclude-begin inside the range opened at line ${open.line}`);
      if (!Object.hasOwn(RANGE_KINDS, kind)) problems.push(`${file}:${lineNo}: unknown range kind "${kind}" (allowed: ${Object.keys(RANGE_KINDS).join(', ')})`);
      if (!reason) problems.push(`${file}:${lineNo}: exclude-begin(${kind}) has no reason`);
      if (kind === 'dead' && !reason.startsWith(DEAD_REASON)) problems.push(`${file}:${lineNo}: a dead range must say "${DEAD_REASON}"`);
      open = { line: lineNo, kind, reason };
      return;
    }
    if (RANGE_END.test(text)) {
      if (!open) {
        problems.push(`${file}:${lineNo}: exclude-end without an exclude-begin`);
        return;
      }
      ranges.push({ start: open.line + 1, end: lineNo - 1, kind: open.kind, reason: open.reason });
      open = null;
    }
  });
  if (open) problems.push(`${file}:${open.line}: exclude-begin(${open.kind}) has no exclude-end`);
  return { ranges, problems };
}

const inRanges = (line, ranges) => ranges.some((r) => line >= r.start && line <= r.end);

// Regions and functions of one file from its llvm-cov function records, the
// way llvm-cov's own file summary counts them, leaving out what starts inside
// `ranges`. A region entry is [lineStart, colStart, lineEnd, colEnd, count,
// fileId, expandedFileId, kind]; kind 0 is a code region.
function llvmCounts(records, ranges) {
  const groups = new Map();
  for (const record of records) {
    const [line, column] = record.regions[0];
    const key = `${line}:${column}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(record);
  }
  const out = { regions: [0, 0], functions: [0, 0] };
  for (const group of groups.values()) {
    if (inRanges(group[0].regions[0][0], ranges)) continue;
    out.functions[1] += 1;
    if (group.some((record) => record.count > 0)) out.functions[0] += 1;
    let total = 0;
    let covered = 0;
    for (const record of group) {
      const code = record.regions.filter((r) => r[7] === 0 && r[5] === 0 && !inRanges(r[0], ranges));
      total = Math.max(total, code.length);
      covered = Math.max(covered, code.filter((r) => r[4] > 0).length);
    }
    out.regions[1] += total;
    out.regions[0] += covered;
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
  const linesByFile = new Map();
  for (const [file, lines] of Object.entries(archive)) linesByFile.set(rel(file), lines);

  const llvm = readJSON(args.llvm);
  const llvmByFile = new Map();
  for (const f of llvm.data?.[0]?.files ?? []) llvmByFile.set(rel(f.filename), f.summary);
  const recordsByFile = new Map();
  for (const record of llvm.data?.[0]?.functions ?? []) {
    const file = rel(record.filenames?.[0] ?? '');
    if (!recordsByFile.has(file)) recordsByFile.set(file, []);
    recordsByFile.get(file).push(record);
  }

  const targetFiles = new Map(target.files.map((f) => [rel(f.path), f]));
  const generated = [...targetFiles.keys()]
    .filter((file) => !matchesAny(file, WHOLE_INCLUDE))
    .map((file) => ({ path: file, reason: `generated build output (outside ${SOURCE_ROOT})` }));
  const excluded = [...EXCLUDED, ...generated];
  const isExcluded = (file) => matchesAny(file, excluded.map((e) => e.path));

  const mismatches = [];
  const noLlvm = [];
  const recordMismatches = [];
  const rangeProblems = [];
  const rangeExclusions = [];
  // Every target file under SOURCE_ROOT, EXCLUDED ones included: they count
  // in `whole` and never in `gate`.
  const entries = [...targetFiles]
    .filter(([file]) => matchesAny(file, WHOLE_INCLUDE))
    .map(([file, x]) => {
      const excludedFile = isExcluded(file);
      const l = llvmByFile.get(file);
      if (!l) noLlvm.push(file);
      if (l && l.lines.count !== x.executableLines) {
        mismatches.push(`${file}: xccov ${x.executableLines} lines, llvm-cov ${l.lines.count}`);
      }
      const { ranges, problems } = sourceRanges(root, file);
      rangeProblems.push(...problems);
      for (const r of ranges) {
        const reason = r.reason.startsWith(`${r.kind}:`) ? r.reason : `${r.kind}: ${r.reason}`;
        rangeExclusions.push({ path: `${file}:${r.start}-${r.end}`, reason });
      }
      const perLine = linesByFile.get(file) ?? [];
      const executable = perLine.filter((p) => p.isExecutable);
      const outside = executable.filter((p) => !inRanges(p.line, ranges));
      const records = recordsByFile.get(file) ?? [];
      const all = llvmCounts(records, []);
      if (l && (all.regions[0] !== l.regions.covered || all.regions[1] !== l.regions.count
        || all.functions[0] !== l.functions.covered || all.functions[1] !== l.functions.count)) {
        recordMismatches.push(`${file}: records give regions ${all.regions.join('/')}, functions ${all.functions.join('/')}; `
          + `llvm-cov says regions ${l.regions.covered}/${l.regions.count}, functions ${l.functions.covered}/${l.functions.count}`);
      }
      const kept = llvmCounts(records, ranges);
      const hit = (lines) => lines.filter((p) => p.executionCount > 0).length;
      const whole = {
        lines: [hit(executable), executable.length],
        regions: l ? all.regions : [0, 0],
        functions: l ? all.functions : [0, 0],
      };
      const gate = {
        lines: [hit(outside), outside.length],
        regions: l ? kept.regions : [0, 0],
        functions: l ? kept.functions : [0, 0],
      };
      const shown = excludedFile ? executable : outside;
      return {
        path: file,
        gate,
        whole,
        missed: shown.filter((p) => p.executionCount === 0).map((p) => p.line).sort((a, b) => a - b),
        excludedLines: ranges.map((r) => (r.start === r.end ? `${r.start}` : `${r.start}-${r.end}`)).join(','),
        excludedFile,
        inGate: !excludedFile && matchesAny(file, GATE_INCLUDE),
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
    gate: { include: GATE_INCLUDE, ...summarize(entries.filter((e) => e.inGate), 'gate'), unmeasured: gateUnmeasured },
    whole: { include: WHOLE_INCLUDE, target: TARGET_NAME, ...summarize(entries, 'whole'), unmeasured },
    excluded: [...excluded, ...rangeExclusions],
    outsideTarget: OUTSIDE_TARGET,
    perFile: [
      ...entries.map((e) => {
        const shown = e.excludedFile ? e.whole : e.gate;
        const wholeDiffers = !e.excludedFile && e.excludedLines !== '';
        return {
          path: e.path,
          lines: pctOf(shown.lines),
          branches: null,
          regions: pctOf(shown.regions),
          functions: pctOf(shown.functions),
          inGate: e.inGate,
          ...(e.excludedFile ? { excluded: true } : {}),
          linesCovered: shown.lines[0],
          linesTotal: shown.lines[1],
          missedLines: compressLines(e.missed),
          ...(e.excludedLines ? { excludedLines: e.excludedLines } : {}),
          ...(wholeDiffers ? {
            whole: {
              lines: pctOf(e.whole.lines),
              regions: pctOf(e.whole.regions),
              functions: pctOf(e.whole.functions),
              linesCovered: e.whole.lines[0],
              linesTotal: e.whole.lines[1],
            },
          } : {}),
        };
      }),
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
      ...recordMismatches.map((m) => `llvm-cov function records and summary differ: ${m}`),
      ...rangeProblems.map((p) => `malformed range comment: ${p}`),
    ],
  };

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, `${JSON.stringify(summary, null, 2)}\n`);

  const problems = [];
  for (const file of unmeasured) problems.push(`not in the coverage data (cover it or exclude it with a reason): ${file}`);
  for (const m of mismatches) problems.push(`xccov and llvm-cov line totals differ: ${m}`);
  for (const file of noLlvm) problems.push(`no llvm-cov data (regions and functions not counted): ${file}`);
  for (const m of recordMismatches) problems.push(`llvm-cov function records and summary differ: ${m}`);
  for (const p of rangeProblems) problems.push(`malformed range comment: ${p}`);
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
