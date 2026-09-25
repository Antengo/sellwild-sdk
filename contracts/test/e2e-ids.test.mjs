// contracts/e2e/ids.json is the one list of element ids for the sample apps'
// e2e flows. These tests fail when a flow, a sample app or the SDK uses an
// sw.* id that is not listed, and when an entry is malformed.

import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const CONTRACTS_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const ROOT = path.resolve(CONTRACTS_DIR, '..')
const IDS = JSON.parse(fs.readFileSync(path.join(CONTRACTS_DIR, 'e2e', 'ids.json'), 'utf8'))

const ID_FORMAT = /^sw\.[a-z0-9_]+(\.[a-z0-9_]+)+$/
const SETTERS = new Set(['app', 'sdk'])
const SKIP_DIRS = new Set(['node_modules', 'build', 'Pods', 'DerivedData', '.gradle', '.build', '.cxx', 'coverage', '.expo'])
const SOURCE_EXT = /\.(swift|kt|java|ts|tsx|js|jsx|m|mm)$/

/** Every file under `dir` (repo-relative) that `keep` accepts. */
function files(dir, keep) {
  const abs = path.join(ROOT, dir)
  if (!fs.existsSync(abs)) return []
  return fs.readdirSync(abs, { withFileTypes: true }).flatMap((entry) => {
    const rel = path.join(dir, entry.name)
    if (entry.isDirectory()) return SKIP_DIRS.has(entry.name) || entry.name.startsWith('.') ? [] : files(rel, keep)
    return keep(entry.name) ? [rel] : []
  })
}

/** `sw.*` ids in `text`: any such token in a flow, quoted literals in code. */
function idsIn(text, { quotedOnly }) {
  const pattern = quotedOnly ? /["'`](sw\.[a-z0-9_]+(?:\.[a-z0-9_]+)+)["'`]/g : /\b(sw\.[a-z0-9_]+(?:\.[a-z0-9_]+)+)\b/g
  return [...text.matchAll(pattern)].map((m) => m[1])
}

function unlisted(paths, options) {
  const out = []
  for (const file of paths) {
    for (const id of idsIn(fs.readFileSync(path.join(ROOT, file), 'utf8'), options)) {
      if (!(id in IDS.ids)) out.push(`${file}: ${id}`)
    }
  }
  return out
}

describe('contracts/e2e/ids.json', () => {
  it('names the app and its four tabs', () => {
    assert.equal(IDS.app.name, 'Sellwild Sample')
    assert.deepEqual(IDS.app.tabs, ['Feed', 'Ads', 'Listings', 'Diagnostics'])
  })

  it('lists well-formed entries', () => {
    const problems = []
    for (const [id, entry] of Object.entries(IDS.ids)) {
      if (!ID_FORMAT.test(id)) problems.push(`${id}: not sw.<screen>.<thing>`)
      if (typeof entry.description !== 'string' || entry.description.length === 0) problems.push(`${id}: no description`)
      if (typeof entry.screen !== 'string' || entry.screen.length === 0) problems.push(`${id}: no screen`)
      const setters = String(entry.setBy ?? '').split(',').map((s) => s.trim())
      if (!setters.every((s) => SETTERS.has(s))) problems.push(`${id}: setBy must be app, sdk or "app, sdk"`)
      if (setters.includes('sdk') && Object.keys(entry.sdk ?? {}).length === 0) problems.push(`${id}: setBy sdk needs an sdk file`)
      for (const file of Object.values(entry.sdk ?? {})) {
        if (!fs.existsSync(path.join(ROOT, file))) problems.push(`${id}: sdk file ${file} does not exist`)
      }
    }
    assert.deepEqual(problems, [])
  })

  it('has one tab id per tab', () => {
    const tabs = Object.keys(IDS.ids).filter((id) => id.startsWith('sw.tab.'))
    assert.deepEqual(tabs, IDS.app.tabs.map((t) => `sw.tab.${t.toLowerCase()}`))
  })

  it('lists every id the Maestro flows use', () => {
    const flows = files('e2e/maestro', (name) => /\.ya?ml$/.test(name))
    assert.ok(flows.length > 0, 'no flows under e2e/maestro')
    assert.deepEqual(unlisted(flows, { quotedOnly: false }), [])
  })

  it('lists every id the sample apps and the SDKs set', () => {
    const roots = ['samples', 'ios/Sources', 'android/src/main', 'react-native/src', 'react-native/ios', 'react-native/android/src']
    const sources = roots.flatMap((dir) => files(dir, (name) => SOURCE_EXT.test(name)))
    assert.deepEqual(unlisted(sources, { quotedOnly: true }), [])
  })
})
