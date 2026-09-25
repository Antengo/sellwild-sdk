#!/usr/bin/env node
// Prints the steps of one Maestro run, one line each, from the commands.json
// files under a --test-output-dir. With --format junit Maestro's console
// shows only a pass/fail summary; this puts every step in maestro.log.
//
//   node scripts/e2e/lib/maestro-steps.mjs <test-output-dir>
//
// Exit status: 0, or 1 when no commands.json was found.

import fs from 'node:fs'
import path from 'node:path'

const findCommandFiles = (dir) =>
  fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) return findCommandFiles(full)
    return /^commands.*\.json$/.test(entry.name) ? [full] : []
  })

const selector = (s = {}) =>
  [s.idRegex && `id=${s.idRegex}`, s.textRegex && `text=${JSON.stringify(s.textRegex)}`].filter(Boolean).join(' ')

/** One command as a short phrase, e.g. `assert visible id=sw.feed.list`. */
export function describe(command) {
  const [name, body = {}] = Object.entries(command)[0] ?? ['?']
  const timeout = body.timeout ? ` (timeout ${body.timeout}ms)` : ''
  switch (name) {
    case 'launchAppCommand': return `launch ${body.appId}${body.clearState ? ' (clear state)' : ''}`
    case 'tapOnElement': return `tap ${selector(body.selector)}`
    case 'assertConditionCommand': {
      const [kind, s] = Object.entries(body.condition ?? {})[0] ?? ['?', {}]
      return `assert ${kind === 'notVisible' ? 'not visible' : kind} ${selector(s)}${timeout}`
    }
    case 'scrollUntilVisible': return `scroll ${String(body.direction).toLowerCase()} to ${selector(body.selector)}`
    case 'takeScreenshotCommand': return `screenshot ${body.path}`
    case 'runFlowCommand': return `run ${body.sourceDescription ?? 'inline commands'}`
    case 'waitForAnimationToEndCommand': return `wait for animations${timeout}`
    default: return name.replace(/Command$/, '')
  }
}

const HIDDEN = new Set(['defineVariablesCommand', 'applyConfigurationCommand'])

function main(dir) {
  const files = fs.existsSync(dir) ? findCommandFiles(dir) : []
  if (files.length === 0) {
    console.log(`maestro-steps: no commands.json under ${dir}`)
    return 1
  }
  for (const file of files) {
    console.log(`steps (${path.relative(dir, file)}):`)
    for (const { command, metadata = {} } of JSON.parse(fs.readFileSync(file, 'utf8'))) {
      const shown = metadata.evaluatedCommand ?? command
      if (HIDDEN.has(Object.keys(shown)[0])) continue
      const indent = '  '.repeat((metadata.depth ?? 0) + 1)
      const error = metadata.error ? `: ${metadata.error.message ?? JSON.stringify(metadata.error)}` : ''
      console.log(`${indent}${(metadata.status ?? '?').padEnd(9)} ${describe(shown)}${error}`)
    }
  }
  return 0
}

if (import.meta.url === `file://${process.argv[1]}`) process.exit(main(process.argv[2] ?? '.'))
