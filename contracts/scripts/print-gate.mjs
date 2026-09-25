#!/usr/bin/env node
// Print gate (FAILURES.md section 11): counts banned print calls and empty
// catch blocks in shipped SDK source and compares them with
// print-gate.allowlist.json. A file may only go down.
//
//   node scripts/print-gate.mjs            report + exit 1 on any increase
//   node scripts/print-gate.mjs --update   rewrite the allowlist with today's counts
//                                          (refuses increases unless --allow-increase)

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { CONTRACTS_DIR, SDK_ROOT } from './lib/paths.mjs'

export const ALLOWLIST_PATH = path.join(CONTRACTS_DIR, 'print-gate.allowlist.json')

/** Scanned roots, relative to the SDK repo, with the platform each belongs to. */
export const SCAN_ROOTS = [
  { dir: 'core/src', platform: 'core' },
  { dir: 'react-native/src', platform: 'react-native' },
  { dir: 'react-native/ios', platform: 'react-native-ios' },
  { dir: 'react-native/android/src', platform: 'react-native-android' },
  { dir: 'ios/Sources', platform: 'ios' },
  { dir: 'android/src/main', platform: 'android' },
  { dir: 'flutter/lib', platform: 'flutter' },
]

/** A2: the only files allowed to print (debug echo + debug logger per platform). */
export const PRINT_EXEMPT = [
  'core/src/failures/index.ts',
  'core/src/debug-log.ts',
  'ios/Sources/SellwildSDK/Failures/SellwildFailures.swift',
  'ios/Sources/SellwildSDK/Failures/SellwildLog.swift',
  'android/src/main/kotlin/com/sellwild/sdk/failures/SellwildFailures.kt',
  'android/src/main/kotlin/com/sellwild/sdk/failures/SellwildLog.kt',
  'flutter/lib/src/failures/sellwild_failures.dart',
  'flutter/lib/src/failures/sellwild_log.dart',
]

const LANG_BY_EXT = {
  '.ts': 'ts', '.tsx': 'ts', '.js': 'ts', '.jsx': 'ts', '.mjs': 'ts', '.cjs': 'ts',
  '.swift': 'swift', '.kt': 'kotlin', '.kts': 'kotlin', '.java': 'kotlin',
  '.dart': 'dart', '.m': 'objc', '.mm': 'objc', '.h': 'objc',
}
const SKIP_DIR = new Set(['node_modules', 'build', 'dist', '.build', 'test', 'tests', '__tests__', 'androidTest', 'Pods', '.gradle'])
const SKIP_FILE = /\.(test|spec)\.[a-z]+$|\.d\.ts$/

export function langOf(file) {
  return LANG_BY_EXT[path.extname(file)] ?? null
}

// ── Comment stripping ────────────────────────────────────────────────────────

const QUOTES = { ts: ['`', '"', "'"], swift: ['"'], kotlin: ['"', "'"], dart: ['"', "'"], objc: ['"', "'"] }
const TRIPLES = { swift: ['"""'], kotlin: ['"""'], dart: ["'''", '"""'], ts: [], objc: [] }
const NESTED_BLOCKS = new Set(['swift', 'kotlin', 'dart'])

const CODE = 0
const COMMENT = 1
const STRING = 2

/**
 * Classify every character as code, comment or string. Understands nested
 * block comments (Swift/Kotlin/Dart), triple-quoted and raw strings, TS regex
 * literals, and ${…} / \\(…) interpolation (interpolated expressions are code).
 */
export function regions(src, lang) {
  const kind = new Uint8Array(src.length)
  const stack = [{ kind: 'code', open: null, close: null, depth: 0 }]
  let i = 0
  const n = src.length
  const at = (s) => src.startsWith(s, i)
  const mark = (a, b, k) => kind.fill(k, a, b)
  let lastSignificant = ''
  while (i < n) {
    const top = stack[stack.length - 1]
    const ch = src[i]
    if (top.kind === 'code') {
      if (at('//')) {
        const end = src.indexOf('\n', i)
        const stop = end < 0 ? n : end
        mark(i, stop, COMMENT)
        i = stop
        continue
      }
      if (at('/*')) {
        let depth = 0
        let j = i
        while (j < n) {
          if (src.startsWith('/*', j) && (depth === 0 || NESTED_BLOCKS.has(lang))) { depth++; j += 2; continue }
          if (src.startsWith('*/', j)) { depth--; j += 2; if (depth === 0) break; continue }
          j++
        }
        mark(i, j, COMMENT)
        i = j
        continue
      }
      if (lang === 'ts' && ch === '/' && (lastSignificant === '' || '(,=:[!&|?{};+-*%<>~^'.includes(lastSignificant))) {
        // Regex literal: skip to the closing slash outside a character class.
        let j = i + 1
        let inClass = false
        while (j < n && src[j] !== '\n') {
          if (src[j] === '\\') { j += 2; continue }
          if (src[j] === '[') inClass = true
          else if (src[j] === ']') inClass = false
          else if (src[j] === '/' && !inClass) break
          j++
        }
        if (j < n && src[j] === '/') {
          mark(i, j + 1, STRING)
          i = j + 1
          lastSignificant = '/'
          continue
        }
      }
      const raw = lang === 'dart' && ch === 'r' && /["']/.test(src[i + 1] ?? '') && !/[\w$]/.test(src[i - 1] ?? '')
      const qStart = raw ? i + 1 : i
      const triple = (TRIPLES[lang] ?? []).find((t) => src.startsWith(t, qStart))
      if (triple) {
        stack.push({ kind: 'str', quote: triple, raw, multiline: true })
        mark(i, qStart + triple.length, STRING)
        i = qStart + triple.length
        continue
      }
      if ((QUOTES[lang] ?? []).includes(src[qStart])) {
        const q = src[qStart]
        stack.push({ kind: 'str', quote: q, raw, multiline: q === '`' })
        mark(i, qStart + 1, STRING)
        i = qStart + 1
        continue
      }
      if (top.close) {
        if (ch === top.open) top.depth++
        else if (ch === top.close) {
          if (top.depth === 0) { stack.pop(); kind[i] = STRING; i++; continue }
          top.depth--
        }
      }
      if (!/\s/.test(ch)) lastSignificant = ch
      i++
      continue
    }
    // Inside a string.
    kind[i] = STRING
    if (!top.raw && ch === '\\') {
      if (lang === 'swift' && src[i + 1] === '(') {
        kind[i + 1] = STRING
        stack.push({ kind: 'code', open: '(', close: ')', depth: 0 })
        i += 2
        continue
      }
      if (i + 1 < n) kind[i + 1] = STRING
      i += 2
      continue
    }
    if (!top.raw && ch === '$' && src[i + 1] === '{' && (lang === 'ts' ? top.quote === '`' : lang === 'kotlin' || lang === 'dart')) {
      kind[i + 1] = STRING
      stack.push({ kind: 'code', open: '{', close: '}', depth: 0 })
      i += 2
      continue
    }
    if (at(top.quote)) {
      mark(i, i + top.quote.length, STRING)
      stack.pop()
      i += top.quote.length
      lastSignificant = '"'
      continue
    }
    if (ch === '\n' && !top.multiline) {
      kind[i] = CODE
      stack.pop()
      i++
      continue
    }
    i++
  }
  return kind
}

function view(src, kind, keep) {
  let out = ''
  for (let i = 0; i < src.length; i++) out += src[i] === '\n' || keep.includes(kind[i]) ? src[i] : ' '
  return out
}

/** Source with comments blanked (newlines and offsets kept); strings stay. */
export function stripComments(src, lang) {
  return view(src, regions(src, lang), [CODE, STRING])
}

/** Three blanked views: code only, strings only, and code + strings. */
export function views(src, lang) {
  const kind = regions(src, lang)
  return { code: view(src, kind, [CODE]), strings: view(src, kind, [STRING]), noComments: view(src, kind, [CODE, STRING]) }
}

// ── Detectors ────────────────────────────────────────────────────────────────

const CONSOLE = /\bconsole\s*\.\s*(?:log|error|warn|info|debug|trace)\s*\(/g
// A print function called by its module-qualified name counts too: Swift.print,
// Foundation.NSLog, os.os_log, kotlin.io.println. Dart has no fixed module
// name (an import prefix is any name), so a prefixed print is not caught here.
const PRINT_RULES = {
  ts: [CONSOLE],
  swift: [CONSOLE, /(?<![.\w])(?:(?:Swift|Foundation|os)\s*\.\s*)?(?:print|debugPrint|dump|NSLog|os_log)\s*\(/g],
  kotlin: [CONSOLE, /(?<![.\w])(?:kotlin\s*\.\s*io\s*\.\s*)?(?:println|print)\s*\(/g, /\bLog\s*\.\s*(?:e|w|i|d|v|wtf)\s*\(/g, /\.\s*printStackTrace\s*\(/g, /\bSystem\s*\.\s*(?:out|err)\s*\.\s*print/g],
  dart: [CONSOLE, /(?<![.\w])(?:print|debugPrint)\s*\(/g],
  objc: [CONSOLE, /\bNSLog\s*\(/g],
}
const EMPTY = '\\{\\s*\\}'
const EMPTY_CATCH_RULES = {
  ts: [
    new RegExp(`\\bcatch\\s*(?:\\([^)]*\\))?\\s*${EMPTY}`, 'g'),
    new RegExp(`\\.catch\\s*\\(\\s*(?:\\(\\s*[\\w$]*\\s*\\)|[\\w$]+)\\s*=>\\s*(?:${EMPTY}|undefined|null|void\\s+0)\\s*\\)`, 'g'),
  ],
  swift: [new RegExp(`\\bcatch\\b[^{}\\n]*${EMPTY}`, 'g')],
  kotlin: [new RegExp(`\\bcatch\\s*\\([^)]*\\)\\s*${EMPTY}`, 'g')],
  dart: [
    new RegExp(`\\bcatch\\s*\\([^)]*\\)\\s*${EMPTY}`, 'g'),
    new RegExp(`\\}\\s*on\\s+[A-Z][\\w<>?,. ]*?\\s*${EMPTY}`, 'g'),
    new RegExp(`\\.catchError\\s*\\(\\s*\\([^)]*\\)\\s*(?:${EMPTY}|=>\\s*(?:null|${EMPTY}))\\s*\\)`, 'g'),
  ],
  objc: [new RegExp(`@catch\\s*\\([^)]*\\)\\s*${EMPTY}`, 'g')],
}

function hits(text, rules) {
  const found = []
  for (const re of rules) {
    re.lastIndex = 0
    for (const m of text.matchAll(re)) found.push({ index: m.index, text: m[0].replace(/\s+/g, ' ') })
  }
  return found.sort((a, b) => a.index - b.index)
}

const lineOf = (text, index) => text.slice(0, index).split('\n').length

/** Counts for one source text. */
export function scanSource(src, lang, { exemptPrint = false } = {}) {
  const v = views(src, lang)
  const text = v.noComments
  // TS: one view, since page scripts built in template strings are JS too.
  // Other languages: native rules on code only, JS rules on string contents
  // (scripts injected into the WebView).
  const native = lang === 'ts' ? v.noComments : v.code
  const printRules = (PRINT_RULES[lang] ?? []).filter((re) => lang === 'ts' || re !== CONSOLE)
  const prints = exemptPrint ? [] : [
    ...hits(native, printRules),
    ...(lang === 'ts' ? [] : hits(v.strings, [CONSOLE])),
  ].sort((a, b) => a.index - b.index)
  const catches = [
    ...hits(native, EMPTY_CATCH_RULES[lang] ?? []),
    ...(lang === 'ts' ? [] : hits(v.strings, EMPTY_CATCH_RULES.ts)),
  ].sort((a, b) => a.index - b.index)
  return {
    print: prints.length,
    emptyCatch: catches.length,
    hits: [
      ...prints.map((h) => ({ kind: 'print', line: lineOf(text, h.index), text: h.text })),
      ...catches.map((h) => ({ kind: 'emptyCatch', line: lineOf(text, h.index), text: h.text })),
    ],
  }
}

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) {
      if (!SKIP_DIR.has(e.name) && !e.name.startsWith('.')) walk(path.join(dir, e.name), out)
    } else if (langOf(e.name) && !SKIP_FILE.test(e.name)) {
      out.push(path.join(dir, e.name))
    }
  }
  return out
}

/** Scan every root. Returns [{ file, platform, print, emptyCatch, hits }] sorted by file. */
export function scanRepo(root = SDK_ROOT) {
  const results = []
  for (const { dir, platform } of SCAN_ROOTS) {
    for (const abs of walk(path.join(root, dir))) {
      const file = path.relative(root, abs).split(path.sep).join('/')
      const r = scanSource(fs.readFileSync(abs, 'utf8'), langOf(abs), { exemptPrint: PRINT_EXEMPT.includes(file) })
      results.push({ file, platform, ...r })
    }
  }
  return results.sort((a, b) => a.file.localeCompare(b.file))
}

export function readAllowlist(p = ALLOWLIST_PATH) {
  return JSON.parse(fs.readFileSync(p, 'utf8'))
}

/** Compare a scan with the allowlist. Returns { increases, decreases }. */
export function compare(results, allowlist) {
  const increases = []
  const decreases = []
  const seen = new Set()
  for (const r of results) {
    seen.add(r.file)
    const allowed = allowlist.files[r.file] ?? { print: 0, emptyCatch: 0 }
    for (const kind of ['print', 'emptyCatch']) {
      if (r[kind] > (allowed[kind] ?? 0)) increases.push({ file: r.file, kind, allowed: allowed[kind] ?? 0, found: r[kind], hits: r.hits.filter((h) => h.kind === kind) })
      else if (r[kind] < (allowed[kind] ?? 0)) decreases.push({ file: r.file, kind, allowed: allowed[kind], found: r[kind] })
    }
  }
  for (const [file, allowed] of Object.entries(allowlist.files)) {
    if (!seen.has(file)) for (const kind of ['print', 'emptyCatch']) if (allowed[kind]) decreases.push({ file, kind, allowed: allowed[kind], found: 0 })
  }
  return { increases, decreases }
}

export function totalsByPlatform(results) {
  const totals = {}
  for (const { platform } of SCAN_ROOTS) totals[platform] = { files: 0, print: 0, emptyCatch: 0 }
  for (const r of results) {
    const t = totals[r.platform]
    if (r.print || r.emptyCatch) t.files++
    t.print += r.print
    t.emptyCatch += r.emptyCatch
  }
  return totals
}

export function buildAllowlist(results) {
  const files = {}
  for (const r of results) if (r.print || r.emptyCatch) files[r.file] = { print: r.print, emptyCatch: r.emptyCatch }
  return {
    description: 'Per-file counts of banned print calls and empty catch blocks in shipped SDK source (FAILURES.md section 11). The gate fails when a count goes up or a file not listed here has a hit. Lower a count (or drop the file) in the same change that removes a hit: node scripts/print-gate.mjs --update.',
    exemptFromPrint: PRINT_EXEMPT,
    files,
  }
}

function renderTotals(totals) {
  const lines = ['PLATFORM              FILES  PRINT  EMPTY-CATCH']
  let all = { files: 0, print: 0, emptyCatch: 0 }
  for (const [p, t] of Object.entries(totals)) {
    lines.push(`${p.padEnd(20)}  ${String(t.files).padStart(5)}  ${String(t.print).padStart(5)}  ${String(t.emptyCatch).padStart(11)}`)
    all = { files: all.files + t.files, print: all.print + t.print, emptyCatch: all.emptyCatch + t.emptyCatch }
  }
  lines.push(`${'total'.padEnd(20)}  ${String(all.files).padStart(5)}  ${String(all.print).padStart(5)}  ${String(all.emptyCatch).padStart(11)}`)
  return lines.join('\n')
}

function main(argv) {
  const results = scanRepo()
  process.stdout.write(renderTotals(totalsByPlatform(results)) + '\n')
  if (argv.includes('--update')) {
    const next = buildAllowlist(results)
    if (fs.existsSync(ALLOWLIST_PATH) && !argv.includes('--allow-increase')) {
      const { increases } = compare(results, readAllowlist())
      if (increases.length) {
        for (const x of increases) process.stderr.write(`refusing to raise ${x.file} ${x.kind}: ${x.allowed} -> ${x.found}\n`)
        process.exitCode = 1
        return
      }
    }
    fs.writeFileSync(ALLOWLIST_PATH, JSON.stringify(next, null, 2) + '\n')
    process.stdout.write(`wrote ${path.relative(process.cwd(), ALLOWLIST_PATH)}\n`)
    return
  }
  const { increases, decreases } = compare(results, readAllowlist())
  for (const x of increases) {
    process.stdout.write(`FAIL ${x.file} ${x.kind}: allowed ${x.allowed}, found ${x.found}\n`)
    for (const h of x.hits) process.stdout.write(`     line ${h.line}: ${h.text}\n`)
  }
  if (decreases.length) process.stdout.write(`${decreases.length} count(s) went down; run --update to lock them in\n`)
  process.exitCode = increases.length ? 1 : 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main(process.argv.slice(2))
