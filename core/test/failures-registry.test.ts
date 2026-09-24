import { describe, expect, it } from 'vitest'
import { FAILURE_CODES, type FailureCode } from '../src/failures'
import { COMPONENTS, SEVERITIES, normalizeCode } from '../src/failures/core'
import { contract } from './support/contracts'

// contracts/FAILURES.md 4.2: src/failures/codes.ts mirrors the registry codes
// whose clients include core or react-native (React Native re-exports core).

interface RegistryEntry {
  code: string
  component: string
  severity: string
  clients: string[]
}

const registry = contract<RegistryEntry[]>('failure-codes.json')

describe('failure code registry parity', () => {
  it('mirrors exactly the core and react-native codes, in registry order', () => {
    const expected = registry
      .filter((c) => c.clients.includes('core') || c.clients.includes('react-native'))
      .map((c) => c.code)
    expect([...FAILURE_CODES]).toEqual(expected)
  })

  it('holds only codes that pass the format as they are', () => {
    for (const code of FAILURE_CODES) expect(normalizeCode(code), code).toBe(code)
    expect(new Set(FAILURE_CODES).size).toBe(FAILURE_CODES.length)
  })

  it('uses components and severities the pure core knows', () => {
    // client.code.invalid is the one entry with the `unknown` label.
    const labels = [...COMPONENTS, 'unknown']
    for (const code of FAILURE_CODES) {
      const entry = registry.find((c) => c.code === code)!
      expect(labels, code).toContain(entry.component)
      expect(SEVERITIES, code).toContain(entry.severity)
    }
  })

  it('has every code the core call sites use', () => {
    const used: FailureCode[] = [
      'config.fetch.http',
      'config.fetch.network',
      'config.fetch.parse',
      'config.fetch.timeout',
      'config.parse.invalid',
      'listings.fetch.http',
      'listings.fetch.network',
      'listings.fetch.parse',
      'listings.parse.invalid',
    ]
    for (const code of used) expect(FAILURE_CODES).toContain(code)
  })
})
