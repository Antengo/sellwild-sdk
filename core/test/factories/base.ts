// Shared plumbing for the mock factories: every factory starts from a real
// sample or a contracts fixture (never an inline payload literal), drops the
// `_synthetic` marker, and applies typed overrides. Each factory has a test
// that validates its default and every variant against the contract schema,
// and that the contract's invalid fixtures fail (test/factories/*.test.ts).

import { contract, contractFiles, variantName, withoutMarker } from '../support/contracts'
import type { SchemaName } from '../support/schemas'

/** Variant name → loader of its base payload. */
export type Variants = Record<string, () => unknown>

/** Variants from [name, loader] pairs (the test lib is ES2017: no Object.fromEntries). */
export function variantsOf(pairs: Array<[string, () => unknown]>): Variants {
  const out: Variants = {}
  for (const [name, loader] of pairs) out[name] = loader
  return out
}

/** One loader per valid fixture of a schema, named after the file. */
export function fixtureVariants(schema: SchemaName): Variants {
  return variantsOf(
    contractFiles(`fixtures/${schema}/valid`).map((file) => [variantName(file), () => contract(`fixtures/${schema}/valid/${file}`)]),
  )
}

/** One loader per real JSON sample of a schema, named after the file. */
export function sampleVariants(schema: SchemaName): Variants {
  return variantsOf(
    contractFiles(`samples/${schema}`).map((file) => [variantName(file), () => contract(`samples/${schema}/${file}`)]),
  )
}

/** A fresh copy of one variant, marker dropped. Throws on an unknown name. */
export function load<T>(kind: string, variants: Variants, variant: string): T {
  const loader = variants[variant]
  if (!loader) throw new Error(`no ${kind} variant '${variant}' (have: ${Object.keys(variants).join(', ')})`)
  return withoutMarker(loader()) as T
}

export interface InvalidCase {
  name: string
  value: unknown
  /** The ajv error the contract says this fixture must produce. */
  error: { instancePath: string; keyword?: string }
}

/**
 * One invalid contract fixture as it would arrive on the wire (marker
 * dropped). Its factory test proves it fails the schema for the declared
 * reason (expectInvalidCases). Throws on an unknown name.
 */
export function invalidPayload<T = unknown>(schema: SchemaName, name: string): T {
  const found = invalidCases(schema).find((c) => c.name === name)
  if (!found) throw new Error(`no invalid ${schema} fixture '${name}'`)
  return withoutMarker(found.value) as T
}

/** The contract's invalid fixtures for a schema, each with the error it must produce. */
export function invalidCases(schema: SchemaName): InvalidCase[] {
  const expected = contract<{ errors: Record<string, InvalidCase['error']> }>(`fixtures/${schema}/invalid/_expected-errors.json`).errors
  return contractFiles(`fixtures/${schema}/invalid`).map((file) => ({
    name: variantName(file),
    value: contract(`fixtures/${schema}/invalid/${file}`),
    error: expected[file],
  }))
}
