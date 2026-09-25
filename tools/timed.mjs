#!/usr/bin/env node
// Times a test suite and appends one record to <repo>/.timings/suites.jsonl.
//
//   node tools/timed.mjs <suite> -- <cmd> [args...]
//     Runs cmd, streams its output, records wall time, exit code and machine
//     load, and exits with cmd's status. Output lines of the form
//     "::timing <phase> <seconds>" are collected as phase times.
//
//   node tools/timed.mjs --record <suite> --seconds <n> --exit <n> [--phase name=secs ...]
//     Appends a record for a run timed elsewhere (the coverage shell scripts
//     time their own build / test / report phases this way).
//
// TIMING_LABEL (optional) tags the record with who ran it, e.g. an agent name.
import { spawn, execFileSync } from 'node:child_process'
import { appendFileSync, mkdirSync } from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const FILE = process.env.TIMINGS_FILE || path.join(ROOT, '.timings', 'suites.jsonl')

function gitHead () {
  try {
    const head = execFileSync('git', ['-C', ROOT, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim()
    const dirty = execFileSync('git', ['-C', ROOT, 'status', '--porcelain'], { encoding: 'utf8' }).trim() !== ''
    return { head, dirty }
  } catch {
    return { head: null, dirty: null }
  }
}

function append (record) {
  mkdirSync(path.dirname(FILE), { recursive: true })
  appendFileSync(FILE, JSON.stringify(record) + '\n')
}

function base (suite) {
  return {
    suite,
    startedAt: new Date().toISOString(),
    cpus: os.cpus().length,
    load1: Number(os.loadavg()[0].toFixed(2)),
    label: process.env.TIMING_LABEL || null,
    ...gitHead(),
  }
}

const argv = process.argv.slice(2)

if (argv[0] === '--record') {
  const suite = argv[1]
  const rec = { ...base(suite), seconds: null, exit: null, phases: {} }
  for (let i = 2; i < argv.length; i++) {
    const flag = argv[i]
    const value = argv[++i]
    if (flag === '--seconds') rec.seconds = Number(value)
    else if (flag === '--exit') rec.exit = Number(value)
    else if (flag === '--phase') {
      const [name, secs] = value.split('=')
      rec.phases[name] = Number(secs)
    } else if (flag === '--cmd') rec.cmd = value
  }
  append(rec)
  process.exit(0)
}

const sep = argv.indexOf('--')
if (sep < 1 || sep === argv.length - 1) {
  console.error('usage: node tools/timed.mjs <suite> -- <cmd> [args...]')
  process.exit(2)
}
const suite = argv[0]
const [cmd, ...args] = argv.slice(sep + 1)
const rec = { ...base(suite), cmd: [cmd, ...args].join(' '), phases: {} }
const t0 = process.hrtime.bigint()
const PHASE = /^::timing (\S+) ([\d.]+)\s*$/

function scan (stream, out) {
  let buf = ''
  stream.on('data', (chunk) => {
    out.write(chunk)
    buf += chunk.toString()
    const lines = buf.split('\n')
    buf = lines.pop()
    for (const line of lines) {
      const m = PHASE.exec(line)
      if (m) rec.phases[m[1]] = Number(m[2])
    }
  })
}

const child = spawn(cmd, args, { stdio: ['inherit', 'pipe', 'pipe'] })
scan(child.stdout, process.stdout)
scan(child.stderr, process.stderr)
const finish = (code) => {
  rec.seconds = Number((Number(process.hrtime.bigint() - t0) / 1e9).toFixed(2))
  rec.exit = code
  rec.load1End = Number(os.loadavg()[0].toFixed(2))
  append(rec)
  process.exit(code)
}
child.on('error', (err) => {
  process.stderr.write(`timed.mjs: could not start ${cmd}: ${err.message}\n`)
  finish(127)
})
child.on('close', (code, signal) => finish(code ?? (signal ? 128 : 1)))
