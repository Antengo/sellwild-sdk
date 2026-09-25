#!/usr/bin/env node
// Crash-safe mutation runner for verifying that tests catch real breaks.
//
//   node tools/mutate.mjs <spec.json> [--only id,id] [--timeout 300] [--out results.json]
//   node tools/mutate.mjs --recover
//
// spec.json is an array of mutations, run one at a time:
//   { "id": "M1", "file": "core/src/api.ts", "find": "if (!res.ok)", "replace": "if (false)",
//     "test": "npx vitest run core/test/api.test.ts --maxWorkers=2" }
// "file" is relative to the repo root; "test" runs from the repo root through the
// shell. Point "test" at the narrowest command that covers the mutated code (one
// vitest file, one XCTest class via -only-testing, one Gradle --tests filter, one
// dart test file). Never a coverage run.
//
// Each mutation is journaled in .mutation-journal/ BEFORE the file is touched and
// restored in a finally block. If the process dies anyway (killed agent, stopped
// workflow), `--recover` puts back every file that still holds the exact mutated
// text, and leaves alone any file that was edited since.
//
// A mutation is "caught" when the test command exits non-zero (a timeout counts
// as caught: the suite hung). Exit status: 0 when every mutation ran and was
// restored, 1 when a pattern did not match exactly once, 2 on a restore failure.
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const JOURNAL = path.join(ROOT, '.mutation-journal')
const sha = (text) => createHash('sha256').update(text).digest('hex')

function recover () {
  if (!existsSync(JOURNAL)) { console.log('mutate: nothing to recover'); return 0 }
  let status = 0
  for (const name of readdirSync(JOURNAL).filter((n) => n.endsWith('.json'))) {
    const entry = JSON.parse(readFileSync(path.join(JOURNAL, name), 'utf8'))
    const abs = path.join(ROOT, entry.file)
    const current = existsSync(abs) ? readFileSync(abs, 'utf8') : null
    if (current !== null && sha(current) === entry.mutatedSha) {
      writeFileSync(abs, entry.original)
      console.log(`mutate: restored ${entry.file} (mutation ${entry.id})`)
    } else if (current !== null && sha(current) === entry.originalSha) {
      console.log(`mutate: ${entry.file} already restored (mutation ${entry.id})`)
    } else {
      console.log(`mutate: ${entry.file} changed since mutation ${entry.id}; left as is, check it by hand`)
      status = 2
      continue
    }
    rmSync(path.join(JOURNAL, name))
  }
  return status
}

function run (specPath, { only, timeout, out }) {
  const specs = JSON.parse(readFileSync(specPath, 'utf8')).filter((m) => !only || only.includes(m.id))
  mkdirSync(JOURNAL, { recursive: true })
  const results = []
  let status = 0
  for (const m of specs) {
    const abs = path.join(ROOT, m.file)
    const original = readFileSync(abs, 'utf8')
    const count = original.split(m.find).length - 1
    if (count !== 1) {
      results.push({ id: m.id, file: m.file, error: `find text matched ${count} times` })
      console.log(`${m.id} ${m.file}: find text matched ${count} times; skipped`)
      status = Math.max(status, 1)
      continue
    }
    const mutated = original.replace(m.find, m.replace)
    const journalFile = path.join(JOURNAL, `${m.id}.json`)
    writeFileSync(journalFile, JSON.stringify({ id: m.id, file: m.file, original, originalSha: sha(original), mutatedSha: sha(mutated) }))
    const t0 = Date.now()
    let res
    try {
      writeFileSync(abs, mutated)
      res = spawnSync('/bin/sh', ['-c', m.test], { cwd: ROOT, encoding: 'utf8', timeout: (m.timeout ?? timeout) * 1000, killSignal: 'SIGKILL', maxBuffer: 64 * 1024 * 1024 })
    } finally {
      writeFileSync(abs, original)
    }
    const restored = sha(readFileSync(abs, 'utf8')) === sha(original)
    if (restored) rmSync(journalFile)
    else status = 2
    const timedOut = res.error?.code === 'ETIMEDOUT' || res.signal === 'SIGKILL'
    const caught = timedOut || res.status !== 0
    const tail = `${res.stdout ?? ''}${res.stderr ?? ''}`.trim().split('\n').slice(-4).join(' | ').slice(0, 400)
    const seconds = (Date.now() - t0) / 1000
    results.push({ id: m.id, file: m.file, caught, timedOut, seconds, restored, tail })
    console.log(`${m.id} ${caught ? 'CAUGHT ' : 'SURVIVED'} ${seconds.toFixed(1)}s ${m.file}${timedOut ? ' (timeout)' : ''}${restored ? '' : ' RESTORE FAILED'}`)
  }
  if (out) writeFileSync(out, JSON.stringify(results, null, 1))
  const survived = results.filter((r) => r.caught === false).map((r) => r.id)
  console.log(`mutate: ${results.length} run, ${survived.length} survived${survived.length ? ` (${survived.join(', ')})` : ''}`)
  return status
}

const argv = process.argv.slice(2)
if (argv[0] === '--recover') process.exit(recover())
const opt = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null }
if (!argv[0] || argv[0].startsWith('--')) {
  console.error('usage: node tools/mutate.mjs <spec.json> [--only id,id] [--timeout 300] [--out results.json] | --recover')
  process.exit(2)
}
process.exit(run(argv[0], { only: opt('--only')?.split(','), timeout: Number(opt('--timeout') ?? 300), out: opt('--out') }))
