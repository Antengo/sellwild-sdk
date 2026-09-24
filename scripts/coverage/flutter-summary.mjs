#!/usr/bin/env node
// Summarizes flutter/coverage/lcov.info into coverage-summary/flutter.json
// (contract amendment A10).
//
// `flutter test --branch-coverage` writes DA and BRDA records but no BRF/BRH,
// and flutter test collects no function coverage at all (no FN/FNDA/FNF/FNH).
// Totals therefore come from LF/LH, BRF/BRH and FNF/FNH when present and are
// computed from DA, BRDA and FN/FNDA otherwise. With no function records
// anywhere, `functions` is null rather than a made-up number.
//
// Honesty checks, reported in the JSON and on stderr:
//   - lib/ files missing from lcov.info ("unmeasured"): no test loaded them, or
//     they have no executable lines. Either load them from a test or add them
//     to EXCLUDED with a reason. Directive-only barrels are excluded
//     automatically. An unmeasured file has no line count, so a percentage
//     over the rest would overstate coverage: while any file in a scope is
//     unmeasured, that scope's pct values are null and `complete` is false.
//     The covered/total counts stay, labeled as measured files only.
//   - every `// coverage:ignore-*` comment in lib/, with its reason text. An
//     ignore without a reason is flagged.
//
// Usage:
//   node flutter-summary.mjs --lcov <lcov.info> --pkg <flutter dir> --out <json>
//     [--command "<cmd>"]... [--tests-exit <n>] [--contracts <status>]
//     [--contracts-harness <status>] [--enforce]
// --contracts is validate.mjs on the tests' factory output (--out flutter);
// --contracts-harness is validate.mjs on the support self-test's round-trip
// (--out flutter-harness), which never counts as factory output.
// --enforce exits 2 when the gate is under 95% lines or branches, or a check
// above fails. Without it the script exits 0 once the summary is written.

import fs from 'node:fs';
import path from 'node:path';

const TARGET_PCT = 95;
const GATE_INCLUDE = ['lib/src/**'];
const WHOLE_INCLUDE = ['lib/**'];

// A10 allows exclusions only for type-only files, generated output, tiny entry
// bootstraps, third-party SDK init that needs a device or network, and dead
// code pending a delete decision. Each entry: { path: '<glob>', reason: '...' }.
const EXCLUDED = [];

const NOTES = [
  'functions is null: flutter test does not collect function coverage (flutter_tools test/coverage_collector.dart never passes functionCoverage to package:coverage), so lcov.info has no FN/FNDA records.',
  'complete is false when a file in that scope is missing from lcov.info; its pct values are then null, and covered/total count measured files only.',
  'regions is null: Dart coverage has no region data.',
  'branches come from Dart VM branch coverage (BRDA). A branch counts as covered when its taken count is above 0.',
  'JavaScript inside Dart string literals (sellwild_widget.dart HTML builders) counts as covered once the Dart builder runs; its runtime behavior is not measured here.',
  'Lines under // coverage:ignore-* comments are dropped by flutter test before lcov.info is written; every such comment is listed in ignoredLines.',
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
      case '--lcov': args.lcov = value(); break;
      case '--pkg': args.pkg = value(); break;
      case '--out': args.out = value(); break;
      case '--command': args.commands.push(value()); break;
      case '--tests-exit': args.testsExit = Number(value()); break;
      case '--contracts': args.contracts = value(); break;
      case '--contracts-harness': args.contractsHarness = value(); break;
      case '--enforce': args.enforce = true; break;
      default: throw new Error(`unknown argument ${flag}`);
    }
  }
  for (const required of ['lcov', 'pkg', 'out']) {
    if (!args[required]) throw new Error(`--${required} is required`);
  }
  return args;
}

function parseLcov(text) {
  const files = new Map();
  let current = null;
  const int = (s) => Number.parseInt(s, 10);
  for (const raw of text.split('\n')) {
    const line = raw.trim();
    if (line.startsWith('SF:')) {
      current = {
        path: line.slice(3),
        da: new Map(),
        brda: [],
        fn: new Map(),
        fnda: new Map(),
        summary: {},
      };
      files.set(current.path, current);
      continue;
    }
    if (!current) continue;
    if (line === 'end_of_record') {
      current = null;
      continue;
    }
    const colon = line.indexOf(':');
    if (colon < 0) continue;
    const tag = line.slice(0, colon);
    const body = line.slice(colon + 1);
    const parts = body.split(',');
    switch (tag) {
      case 'DA': {
        const lineNo = int(parts[0]);
        current.da.set(lineNo, (current.da.get(lineNo) ?? 0) + int(parts[1]));
        break;
      }
      case 'BRDA':
        current.brda.push({ line: int(parts[0]), block: parts[1], branch: parts[2], taken: parts[3] });
        break;
      case 'FN':
        current.fn.set(parts.slice(1).join(','), int(parts[0]));
        break;
      case 'FNDA':
        current.fnda.set(parts.slice(1).join(','), int(parts[0]));
        break;
      case 'LF': case 'LH': case 'BRF': case 'BRH': case 'FNF': case 'FNH':
        current.summary[tag] = int(body);
        break;
      default:
        break;
    }
  }
  return files;
}

function counts(covered, total) {
  return { covered, total, pct: total === 0 ? null : Math.round((covered / total) * 10000) / 100 };
}

function fileTotals(rec) {
  const s = rec.summary;
  const linesTotal = s.LF ?? rec.da.size;
  const linesCovered = s.LH ?? [...rec.da.values()].filter((hits) => hits > 0).length;
  const hasBranches = s.BRF !== undefined || rec.brda.length > 0;
  const branchesTotal = s.BRF ?? rec.brda.length;
  const branchesCovered = s.BRH ?? rec.brda.filter((b) => b.taken !== '-' && Number(b.taken) > 0).length;
  const hasFunctions = s.FNF !== undefined || rec.fn.size > 0;
  const functionsTotal = s.FNF ?? rec.fn.size;
  const functionsCovered = s.FNH ?? [...rec.fn.keys()].filter((name) => (rec.fnda.get(name) ?? 0) > 0).length;
  return {
    lines: [linesCovered, linesTotal],
    branches: hasBranches ? [branchesCovered, branchesTotal] : null,
    functions: hasFunctions ? [functionsCovered, functionsTotal] : null,
  };
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

function listDartFiles(pkg, dir) {
  const root = path.join(pkg, dir);
  if (!fs.existsSync(root)) return [];
  const out = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true, recursive: true })) {
    if (entry.isFile() && entry.name.endsWith('.dart')) {
      out.push(path.relative(pkg, path.join(entry.parentPath ?? entry.path, entry.name)).split(path.sep).join('/'));
    }
  }
  return out.sort();
}

// True when a file holds only comments and library/import/export/part
// directives (a barrel). Such a file has no executable lines, so it never
// shows up in lcov.info and is not "unmeasured".
function isDirectivesOnly(text) {
  const code = text
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, '').trim())
    .filter((line) => line.length > 0)
    .join('\n');
  const statements = code.split(';').map((st) => st.trim()).filter((st) => st.length > 0);
  return statements.every((st) => /^(library|import|export|part)\b/.test(st));
}

const IGNORE_RE = /\/\/\s*coverage:(ignore-line|ignore-start|ignore-end|ignore-file)\b[\s:—–-]*(.*)$/;

// Every coverage:ignore-* comment, with the text after it as the reason.
// ignore-end closes a block and needs no reason of its own.
function scanIgnores(pkg, files) {
  const ignores = [];
  for (const file of files) {
    const lines = fs.readFileSync(path.join(pkg, file), 'utf8').split('\n');
    lines.forEach((text, index) => {
      const m = IGNORE_RE.exec(text);
      if (!m) return;
      const reason = m[2].trim() || null;
      ignores.push({ path: file, line: index + 1, directive: m[1], reason });
    });
  }
  return ignores;
}

function aggregate(entries, key) {
  const present = entries.filter((e) => e.totals[key] !== null);
  if (present.length === 0) return null;
  const covered = present.reduce((sum, e) => sum + e.totals[key][0], 0);
  const total = present.reduce((sum, e) => sum + e.totals[key][1], 0);
  return counts(covered, total);
}

// Totals for one scope. With unmeasured files the pct values are withheld
// (null), since the missing files would only lower them.
function summarize(entries, unmeasured) {
  const complete = unmeasured.length === 0;
  const scope = (metric) => (metric === null || complete ? metric : { ...metric, pct: null });
  return {
    complete,
    lines: scope(aggregate(entries, 'lines')),
    branches: scope(aggregate(entries, 'branches')),
    regions: null,
    functions: scope(aggregate(entries, 'functions')),
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const pkg = path.resolve(args.pkg);
  const lcovText = fs.readFileSync(args.lcov, 'utf8');
  const records = parseLcov(lcovText);
  if (records.size === 0) throw new Error(`${args.lcov} has no SF records`);

  const libFiles = listDartFiles(pkg, 'lib');
  const ignores = scanIgnores(pkg, libFiles);
  const ignoredFiles = new Map(
    ignores.filter((i) => i.directive === 'ignore-file').map((i) => [i.path, i.reason]),
  );
  const barrels = libFiles.filter((file) => isDirectivesOnly(fs.readFileSync(path.join(pkg, file), 'utf8')));
  const excluded = [
    ...EXCLUDED,
    ...barrels.map((file) => ({ path: file, reason: 'directives only (library/import/export/part): no executable lines' })),
    ...[...ignoredFiles].map(([file, reason]) => ({ path: file, reason: reason ?? 'coverage:ignore-file (no reason given)' })),
  ];
  const isExcluded = (file) => matchesAny(file, excluded.map((e) => e.path));

  const entries = [...records.values()]
    .filter((rec) => matchesAny(rec.path, WHOLE_INCLUDE))
    .map((rec) => ({
      path: rec.path,
      totals: fileTotals(rec),
      missed: [...rec.da].filter(([, hits]) => hits === 0).map(([line]) => line).sort((a, b) => a - b),
      missedBranch: [...new Set(rec.brda.filter((b) => b.taken === '-' || Number(b.taken) === 0).map((b) => b.line))].sort((a, b) => a - b),
      inGate: matchesAny(rec.path, GATE_INCLUDE) && !isExcluded(rec.path),
    }))
    .sort((a, b) => a.path.localeCompare(b.path));

  const measured = new Set(entries.map((e) => e.path));
  const unmeasured = libFiles.filter((file) => !measured.has(file) && !isExcluded(file));
  const gateUnmeasured = unmeasured.filter((file) => matchesAny(file, GATE_INCLUDE));
  const unreasoned = ignores.filter((i) => i.directive !== 'ignore-end' && i.reason === null);

  const pctOf = (pair) => (pair === null ? null : counts(pair[0], pair[1]).pct);
  const summary = {
    platform: 'flutter',
    generatedAt: new Date().toISOString(),
    tool: 'flutter test --coverage --branch-coverage (package:coverage lcov)',
    commands: args.commands,
    gate: { include: GATE_INCLUDE, ...summarize(entries.filter((e) => e.inGate), gateUnmeasured), unmeasured: gateUnmeasured },
    whole: { include: WHOLE_INCLUDE, ...summarize(entries, unmeasured), unmeasured },
    excluded,
    ignoredLines: ignores,
    perFile: [
      ...entries.map((e) => ({
        path: e.path,
        lines: pctOf(e.totals.lines),
        branches: pctOf(e.totals.branches),
        functions: pctOf(e.totals.functions),
        inGate: e.inGate,
        linesCovered: e.totals.lines[0],
        linesTotal: e.totals.lines[1],
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
    tests: args.testsExit === undefined ? null : { exitCode: args.testsExit, passed: args.testsExit === 0 },
    contracts: args.contracts ?? null,
    contractsHarness: args.contractsHarness ?? null,
    notes: NOTES,
  };

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, `${JSON.stringify(summary, null, 2)}\n`);

  const problems = [];
  for (const file of unmeasured) problems.push(`not in lcov.info (load it from a test or exclude it with a reason): ${file}`);
  for (const i of unreasoned) problems.push(`coverage:${i.directive} without a reason: ${i.path}:${i.line}`);
  const below = (metric) => metric !== null && metric.total > 0 && (metric.covered / metric.total) * 100 < TARGET_PCT;
  const pctText = (m) => `${counts(m.covered, m.total).pct}%${m.pct === null ? ' (measured files only)' : ''}`;
  if (below(summary.gate.lines)) problems.push(`gate lines ${pctText(summary.gate.lines)} < ${TARGET_PCT}%`);
  if (below(summary.gate.branches)) problems.push(`gate branches ${pctText(summary.gate.branches)} < ${TARGET_PCT}%`);

  const fmt = (m) => {
    if (m === null) return 'n/a';
    return m.pct === null ? `${m.covered}/${m.total} measured files only (pct withheld)` : `${m.covered}/${m.total} (${m.pct}%)`;
  };
  process.stdout.write(
    `flutter coverage -> ${args.out}\n` +
    `  gate  lines ${fmt(summary.gate.lines)}  branches ${fmt(summary.gate.branches)}\n` +
    `  whole lines ${fmt(summary.whole.lines)}  branches ${fmt(summary.whole.branches)}\n`,
  );
  for (const p of problems) process.stderr.write(`  ! ${p}\n`);
  if (args.enforce && problems.length > 0) process.exitCode = 2;
}

try {
  main();
} catch (error) {
  process.stderr.write(`flutter-summary: ${error.message}\n`);
  process.exitCode = 1;
}
