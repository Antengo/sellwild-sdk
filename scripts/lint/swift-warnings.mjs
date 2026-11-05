#!/usr/bin/env node
// Swift compiler-warnings ratchet. Counts the unique compiler warnings in our
// Swift (ios/Sources, ios/Tests) from the last `bash scripts/coverage/ios.sh`
// run and fails when the count is above swift-warnings.baseline.json. It never
// builds anything itself.
//
//   node scripts/lint/swift-warnings.mjs            check (exit 1 on new warnings)
//   node scripts/lint/swift-warnings.mjs --update   lower the baseline after fixing warnings
//                                                   (refuses to raise it unless --allow-increase)
//   --log <file>   the xcodebuild log (default .coverage-tmp/ios-test.log)
//
// Two sources, merged and de-duplicated:
// 1. The xcodebuild log that ios.sh keeps. It only holds warnings for files
//    that build recompiled, so a no-op incremental build logs none at all.
// 2. The serialized diagnostics (.dia) the Swift compiler leaves in derived
//    data for every file it compiled, kept across incremental builds. These
//    make the count complete no matter how much the last build recompiled.
//
// Exit 2 (refuses to run) when the log is missing, is older than the newest
// change under ios/Sources, ios/Tests or Package.swift, or is from a failed
// build. Run bash scripts/coverage/ios.sh, then run this again.

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
export const BASELINE_PATH = path.join(path.dirname(fileURLToPath(import.meta.url)), 'swift-warnings.baseline.json')
const DEFAULT_LOG = '.coverage-tmp/ios-test.log'
const DEFAULT_DERIVED = '.coverage-tmp/ios-dd'
/** Our Swift. Everything else (SourcePackages checkouts, SDK headers, the linker) is left out. */
export const OUR_DIRS = ['ios/Sources/', 'ios/Tests/']
/** A change to any of these makes the log stale. */
const FRESHNESS_INPUTS = ['ios/Sources', 'ios/Tests', 'Package.swift']

// ── Log ──────────────────────────────────────────────────────────────────────

const WARNING_LINE = /^(\S.*?\.swift):(\d+):(\d+): warning: (.+?)\s*$/
const BUILD_FAILED = /\*\* (?:TEST )?BUILD FAILED \*\*|Testing cancelled because the build failed/

/** Drops the " [#group]" suffix newer compilers add in text output; .dia keeps it apart. */
export const cleanMessage = (m) => m.replace(/\s*\[#[\w-]+\]\s*$/, '').trim()

/** Repo-relative path when `file` is one of our Swift files, else null. */
export function ourFile(file, root) {
  const abs = path.resolve(root, file)
  const rel = path.relative(root, abs).split(path.sep).join('/')
  return OUR_DIRS.some((d) => rel.startsWith(d)) ? rel : null
}

/**
 * Parses an xcodebuild log. Returns the derived-data path from the command
 * line (or null), whether the build failed, and our warnings.
 */
export function parseLog(text, root) {
  const derived = /-derivedDataPath\s+("[^"]+"|\S+)/.exec(text)?.[1]?.replace(/^"|"$/g, '') ?? null
  const warnings = []
  for (const raw of text.split(/\r?\n/)) {
    const m = WARNING_LINE.exec(raw)
    if (!m) continue
    const file = ourFile(m[1], root)
    if (file) warnings.push({ file, line: Number(m[2]), column: Number(m[3]), message: cleanMessage(m[4]) })
  }
  return { derivedData: derived, buildFailed: BUILD_FAILED.test(text), warnings }
}

// ── Serialized diagnostics (.dia) ────────────────────────────────────────────
// LLVM bitstream, clang's serialized-diagnostics schema (Swift writes the same).

const BLOCK_INFO = 0
const BLOCK_DIAG = 9
const RECORD_DIAG = 2
const RECORD_FILENAME = 6
export const SEVERITY = { 0: 'ignored', 1: 'note', 2: 'warning', 3: 'error', 4: 'fatal', 5: 'remark' }
const CHAR6 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._'

class BitReader {
  constructor(buf) { this.buf = buf; this.pos = 0 }
  get left() { return this.buf.length * 8 - this.pos }
  read(width) {
    if (width > this.left) throw new Error('bitstream: read past end')
    let v = 0
    for (let i = 0; i < width; i++) {
      const p = this.pos + i
      if ((this.buf[p >> 3] >> (p & 7)) & 1) v += 2 ** i
    }
    this.pos += width
    return v
  }
  vbr(width) {
    if (width === 0) return 0
    const hi = 2 ** (width - 1)
    let v = 0
    for (let shift = 0; shift <= 64; shift += width - 1) {
      const piece = this.read(width)
      v += (piece % hi) * 2 ** shift
      if (piece < hi) return v
    }
    throw new Error('bitstream: VBR too long')
  }
  align32() { this.pos = Math.min(Math.ceil(this.pos / 32) * 32, this.buf.length * 8) }
}

/** Every diagnostic in a .dia buffer: { severity, file, line, column, message }. */
export function readDia(buf) {
  if (buf.length < 4 || buf.toString('latin1', 0, 4) !== 'DIAG') throw new Error('not a serialized diagnostics file')
  const r = new BitReader(buf.subarray(4))
  const blockInfo = new Map()
  const files = new Map()
  const diags = []

  const readAbbrev = () => {
    const ops = []
    for (let n = r.vbr(5); n > 0; n--) {
      if (r.read(1)) { ops.push({ kind: 'literal', value: r.vbr(8) }); continue }
      const enc = r.read(3)
      if (enc === 1) ops.push({ kind: 'fixed', width: r.vbr(5) })
      else if (enc === 2) ops.push({ kind: 'vbr', width: r.vbr(5) })
      else if (enc === 3) ops.push({ kind: 'array' })
      else if (enc === 4) ops.push({ kind: 'char6' })
      else if (enc === 5) ops.push({ kind: 'blob' })
      else throw new Error(`bitstream: bad abbrev encoding ${enc}`)
    }
    return ops
  }
  const scalar = (op) => {
    if (op.kind === 'literal') return op.value
    if (op.kind === 'fixed') return r.read(op.width)
    if (op.kind === 'vbr') return r.vbr(op.width)
    if (op.kind === 'char6') return CHAR6.charCodeAt(r.read(6))
    throw new Error(`bitstream: ${op.kind} is not a scalar`)
  }
  const readRecord = (id, abbrevs) => {
    if (id === 3) {
      const code = r.vbr(6)
      const ops = []
      for (let n = r.vbr(6); n > 0; n--) ops.push(r.vbr(6))
      return { code, ops, blob: null }
    }
    const abbrev = abbrevs[id - 4]
    if (!abbrev) throw new Error(`bitstream: unknown abbrev ${id}`)
    const vals = []
    let blob = null
    for (let i = 0; i < abbrev.length; i++) {
      const op = abbrev[i]
      if (op.kind === 'array') {
        const elt = abbrev[++i]
        for (let n = r.vbr(6); n > 0; n--) vals.push(scalar(elt))
      } else if (op.kind === 'blob') {
        const len = r.vbr(6)
        r.align32()
        const start = r.pos / 8
        if (start + len > r.buf.length) throw new Error('bitstream: blob past end')
        blob = r.buf.toString('utf8', start, start + len)
        r.pos += len * 8
        r.align32()
      } else {
        vals.push(scalar(op))
      }
    }
    return { code: vals[0], ops: vals.slice(1), blob }
  }
  const text = (rec, from) => rec.blob ?? String.fromCharCode(...rec.ops.slice(from))
  const onRecord = (blockId, rec) => {
    if (blockId !== BLOCK_DIAG) return
    if (rec.code === RECORD_FILENAME) files.set(rec.ops[0], text(rec, 4))
    else if (rec.code === RECORD_DIAG) {
      const [severity, fileId, line, column] = rec.ops
      diags.push({ severity: SEVERITY[severity] ?? String(severity), file: files.get(fileId) ?? null, line, column, message: text(rec, 8) })
    }
  }
  const readBlock = (blockId, width) => {
    const abbrevs = [...(blockInfo.get(blockId) ?? [])]
    let infoTarget = null
    for (;;) {
      const id = r.read(width)
      if (id === 0) { r.align32(); return }
      if (id === 1) {
        const inner = r.vbr(8)
        const innerWidth = r.vbr(4)
        r.align32()
        r.read(32) // block length in words
        readBlock(inner, innerWidth)
      } else if (id === 2) {
        const abbrev = readAbbrev()
        if (blockId !== BLOCK_INFO) abbrevs.push(abbrev)
        else if (infoTarget === null) throw new Error('bitstream: abbrev before SETBID')
        else blockInfo.get(infoTarget).push(abbrev)
      } else {
        const rec = readRecord(id, abbrevs)
        if (blockId === BLOCK_INFO) {
          if (rec.code === 1) { // SETBID
            infoTarget = rec.ops[0]
            if (!blockInfo.has(infoTarget)) blockInfo.set(infoTarget, [])
          }
        } else {
          onRecord(blockId, rec)
        }
      }
    }
  }
  while (r.left >= 32) {
    const id = r.read(2)
    if (id !== 1) throw new Error(`bitstream: expected a block at the top level, got abbrev ${id}`)
    const blockId = r.vbr(8)
    const width = r.vbr(4)
    r.align32()
    r.read(32)
    readBlock(blockId, width)
  }
  return diags
}

function findDia(dir, out = []) {
  if (!fs.existsSync(dir)) return out
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) findDia(p, out)
    else if (e.name.endsWith('.dia')) out.push(p)
  }
  return out
}

/** Our warnings from every .dia under the SellwildSDK package's build folder. */
export function diaWarnings(derivedData, root, exists = fs.existsSync) {
  const dir = path.join(derivedData, 'Build/Intermediates.noindex/SellwildSDK.build')
  const files = findDia(dir)
  const warnings = []
  for (const f of files) {
    let diags
    try {
      diags = readDia(fs.readFileSync(f))
    } catch (err) {
      throw new Error(`${path.relative(root, f)}: ${err.message}`)
    }
    for (const d of diags) {
      if (d.severity !== 'warning' || !d.file) continue
      const file = ourFile(d.file, root)
      // A .dia outlives its source when a file is renamed or deleted.
      if (file && exists(path.join(root, file))) warnings.push({ file, line: d.line, column: d.column, message: cleanMessage(d.message) })
    }
  }
  return { files: files.length, warnings }
}

// ── Ratchet ──────────────────────────────────────────────────────────────────

/** Unique by file, line and message (the log and .dia can disagree on columns). */
export function unique(warnings) {
  const seen = new Map()
  for (const w of warnings) {
    const k = `${w.file}:${w.line}: ${w.message}`
    if (!seen.has(k)) seen.set(k, w)
  }
  return [...seen.values()].sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line || a.message.localeCompare(b.message))
}

/** Baseline entry: no line number, so moving code does not look like a new warning. */
export const entryOf = (w) => `${w.file}: ${w.message}`

/** Warnings not covered by the baseline's entries (counted, so a second copy is new). */
export function newWarnings(warnings, baseline) {
  const left = new Map()
  for (const e of baseline.warnings) left.set(e, (left.get(e) ?? 0) + 1)
  return warnings.filter((w) => {
    const n = left.get(entryOf(w)) ?? 0
    if (n > 0) { left.set(entryOf(w), n - 1); return false }
    return true
  })
}

export function buildBaseline(warnings) {
  return {
    description: 'Unique Swift compiler warnings in ios/Sources and ios/Tests, from the last scripts/coverage/ios.sh run. The gate fails when count goes up. Lower it in the same change that removes warnings: node scripts/lint/swift-warnings.mjs --update.',
    count: warnings.length,
    warnings: warnings.map(entryOf).sort(),
  }
}

/** Newest mtime under the inputs: { file, mtimeMs }. */
export function newestInput(root, inputs = FRESHNESS_INPUTS) {
  let best = { file: null, mtimeMs: 0 }
  const visit = (p) => {
    const st = fs.statSync(p)
    if (st.isDirectory()) {
      for (const e of fs.readdirSync(p)) if (!e.startsWith('.')) visit(path.join(p, e))
    } else if (st.mtimeMs > best.mtimeMs) {
      best = { file: path.relative(root, p), mtimeMs: st.mtimeMs }
    }
  }
  for (const i of inputs) if (fs.existsSync(path.join(root, i))) visit(path.join(root, i))
  return best
}

function refuse(msg) {
  process.stderr.write(`swift-warnings: ${msg}\n`)
  return 2
}

const opt = (argv, name) => {
  const i = argv.indexOf(name)
  return i >= 0 ? argv[i + 1] : undefined
}

/** CLI. --root and --baseline exist for the tests; the gate uses the defaults. */
export function main(argv) {
  const root = path.resolve(opt(argv, '--root') ?? ROOT)
  const baselinePath = path.resolve(opt(argv, '--baseline') ?? BASELINE_PATH)
  const logPath = path.resolve(opt(argv, '--log') ?? path.join(root, DEFAULT_LOG))
  const rel = (p) => path.relative(root, p)
  const rerun = 'Run bash scripts/coverage/ios.sh, then run this again.'
  if (!fs.existsSync(logPath)) return refuse(`no xcodebuild log at ${rel(logPath)}. ${rerun}`)
  const logMtime = fs.statSync(logPath).mtimeMs
  const newest = newestInput(root)
  if (newest.mtimeMs > logMtime) {
    return refuse(`stale log: ${newest.file} changed at ${new Date(newest.mtimeMs).toISOString()}, after ${rel(logPath)} was written (${new Date(logMtime).toISOString()}). ${rerun}`)
  }
  const log = parseLog(fs.readFileSync(logPath, 'utf8'), root)
  if (log.buildFailed) return refuse(`${rel(logPath)} is from a failed build, so its warnings are incomplete. ${rerun}`)
  const derived = path.resolve(root, log.derivedData ?? DEFAULT_DERIVED)
  const dia = diaWarnings(derived, root)
  if (dia.files === 0) return refuse(`no .dia files under ${rel(derived)}, so the count would only cover what the last build recompiled. ${rerun}`)

  const warnings = unique([...log.warnings, ...dia.warnings])
  const baseline = fs.existsSync(baselinePath) ? JSON.parse(fs.readFileSync(baselinePath, 'utf8')) : null
  process.stdout.write(`swift-warnings: ${warnings.length} warning(s) in ${OUR_DIRS.join(' + ')} (baseline ${baseline?.count ?? 'none'}; ${log.warnings.length} in the log, ${dia.files} .dia files read)\n`)

  if (argv.includes('--update')) {
    if (baseline && warnings.length > baseline.count && !argv.includes('--allow-increase')) {
      for (const w of newWarnings(warnings, baseline)) process.stderr.write(`  new ${w.file}:${w.line}:${w.column}: ${w.message}\n`)
      process.stderr.write(`swift-warnings: refusing to raise the baseline ${baseline.count} -> ${warnings.length} (pass --allow-increase; needs a reviewer).\n`)
      return 1
    }
    fs.writeFileSync(baselinePath, JSON.stringify(buildBaseline(warnings), null, 2) + '\n')
    process.stdout.write(`wrote ${rel(baselinePath)}\n`)
    return 0
  }
  if (!baseline) return refuse(`no baseline at ${rel(baselinePath)}; create it with --update.`)
  if (warnings.length > baseline.count) {
    process.stdout.write(`FAIL: ${warnings.length} warning(s), baseline allows ${baseline.count}. New:\n`)
    for (const w of newWarnings(warnings, baseline)) process.stdout.write(`  ${w.file}:${w.line}:${w.column}: warning: ${w.message}\n`)
    return 1
  }
  if (warnings.length < baseline.count) process.stdout.write(`count went down (${baseline.count} -> ${warnings.length}); run --update to lock it in\n`)
  return 0
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2))
