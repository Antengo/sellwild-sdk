// Finds the CONSTANT_CASE keys SDK code reads from the remote app config, for
// test/key-coverage.test.mjs.
//
// A key is any quoted CONSTANT_CASE literal in shipped source (comments
// stripped), plus the unquoted keys of core's KEY_MAP. Literals that are not
// config keys are filtered by the rules below.

import fs from 'node:fs'
import path from 'node:path'
import { SDK_ROOT } from './paths.mjs'
import { SCAN_ROOTS, langOf, stripComments } from '../print-gate.mjs'

const CONSTANT = /^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$/

/** Tokens of 1-3 letters are ISO country/currency codes or COL1 layout tokens, not keys. */
export const SHORT_TOKEN = /^[A-Z]{1,3}$/

/** Quoted CONSTANT_CASE literals that are not remote config keys. */
export const NOT_CONFIG_KEYS = {
  POST: 'HTTP method.',
  GAID: 'Advertising id type label sent to GrowthCode.',
  IDFA: 'Advertising id type label sent to GrowthCode.',
  LLGLLGLLG: 'Default COL1 layout value, not a key.',
  SELLER: 'Fallback seller-name text.',
  UNCHECKED_CAST: 'Kotlin @Suppress argument.',
  NO_BIDS: 'Prebid Mobile ResultCode enum name, compared by name in android core/AdDecisions.kt.',
  SUCCESS: 'Prebid Mobile ResultCode enum name, compared by name in android core/AdDecisions.kt.',
  TIMEOUT: 'Prebid Mobile ResultCode enum name, compared by name in android core/AdDecisions.kt.',
  SUCCEEDED: 'Prebid Mobile InitializationStatus enum name, compared by name in android core/PrebidSetup.kt.',
}

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name)
    if (e.isDirectory()) {
      if (!['node_modules', 'build', 'test', 'tests', '__tests__', 'androidTest'].includes(e.name) && !e.name.startsWith('.')) walk(p, out)
    } else if (langOf(e.name) && !/\.(test|spec)\.[a-z]+$|\.d\.ts$/.test(e.name)) {
      out.push(p)
    }
  }
  return out
}

/** Keys referenced by one source text. */
export function keysInSource(src, lang) {
  const text = stripComments(src, lang)
  const keys = new Set()
  for (const m of text.matchAll(/["']([A-Z][A-Z0-9_]*)["']/g)) if (CONSTANT.test(m[1])) keys.add(m[1])
  const keyMap = text.match(/\bKEY_MAP\b[^=]*=\s*\{([\s\S]*?)\n\}/)
  if (keyMap) for (const m of keyMap[1].matchAll(/^\s*([A-Z][A-Z0-9_]*)\s*:/gm)) keys.add(m[1])
  return keys
}

/** Map of key → sorted list of files (relative to the SDK root) that read it. */
export function remoteKeysInRepo(root = SDK_ROOT) {
  const found = new Map()
  for (const { dir } of SCAN_ROOTS) {
    for (const abs of walk(path.join(root, dir))) {
      const rel = path.relative(root, abs).split(path.sep).join('/')
      for (const k of keysInSource(fs.readFileSync(abs, 'utf8'), langOf(abs))) {
        if (!found.has(k)) found.set(k, new Set())
        found.get(k).add(rel)
      }
    }
  }
  return new Map([...found].sort(([a], [b]) => a.localeCompare(b)).map(([k, s]) => [k, [...s].sort()]))
}
