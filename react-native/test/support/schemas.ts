// The contract JSON Schemas (contracts/schemas) in one Ajv 2020-12 instance,
// with the options contracts/scripts/lib/schemas.mjs uses, plus the emit step
// of contracts/README.md: factory output written to
// contracts/out/react-native/<schema>.<variant>.json for
// `node contracts/scripts/validate.mjs --out react-native`.
//
// core/test/support/schemas.ts and factory-checks.ts do the same for core.
// This copy uses this package's ajv and emits to its own folder.

import Ajv2020, { type ErrorObject } from 'ajv/dist/2020'
import addFormats from 'ajv-formats'
import { expect } from 'vitest'
import type { InvalidCase } from '../../../core/test/factories/base'
import { contract, contractFiles } from '../../../core/test/support/contracts'
import type { SchemaName } from '../../../core/test/support/schemas'

export type { SchemaName }

const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true })
addFormats(ajv)
const ids = new Map<string, string>()
for (const file of contractFiles('schemas')) {
  const schema = contract<{ $id: string }>(`schemas/${file}`)
  ajv.addSchema(schema)
  ids.set(file.replace(/\.schema\.json$/, ''), schema.$id)
}

export interface Validation {
  ok: boolean
  errors: ErrorObject[]
  /** Short text of the first errors, for assertion messages. */
  text: string
}

/** Validate a value against a contract schema, or a `#/$defs/...` pointer inside it. */
export function validate(schema: SchemaName, value: unknown, pointer = ''): Validation {
  const id = ids.get(schema)
  if (!id) throw new Error(`no contract schema named ${schema}`)
  const check = ajv.getSchema(`${id}${pointer ? `#${pointer}` : ''}`)
  if (!check) throw new Error(`no schema at ${id}#${pointer}`)
  const ok = check(value) as boolean
  const errors = check.errors ?? []
  return { ok, errors, text: ajv.errorsText(errors) }
}

// ── Emit (contracts/README.md "Emit and validate") ───────────────────────────

interface NodeFs {
  mkdirSync(path: string, options: { recursive: true }): void
  writeFileSync(path: string, data: string): void
}

interface NodeProcess {
  env: Record<string, string | undefined>
  getBuiltinModule?: (id: string) => unknown
}

const CONTRACTS_DIR = decodeURIComponent(new URL('../../../contracts/', import.meta.url).pathname)

/** contracts/out/react-native, or $SELLWILD_CONTRACT_OUT/react-native. */
export function emitDir(): string {
  const env = (globalThis as { process?: NodeProcess }).process?.env ?? {}
  const root = env.SELLWILD_CONTRACT_OUT ?? `${CONTRACTS_DIR}out`
  return `${root.replace(/\/$/, '')}/react-native`
}

/**
 * Write one factory output for validate.mjs. Only valid output is emitted:
 * a full `npm test` in contracts/ checks everything under out/.
 */
export function emit(schema: SchemaName, variant: string, value: unknown): string {
  const fs = (globalThis as { process?: NodeProcess }).process?.getBuiltinModule?.('node:fs') as NodeFs | undefined
  if (!fs) throw new Error('emit needs Node 22.3+ (process.getBuiltinModule)')
  const dir = emitDir()
  fs.mkdirSync(dir, { recursive: true })
  const file = `${dir}/${schema}.${variant}.json`
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n')
  return file
}

// ── Assertions ───────────────────────────────────────────────────────────────

/** Passes `schema` (or a `#/$defs` pointer in it). With `variant`, also emitted to contracts/out/react-native. */
export function expectValid(schema: SchemaName, value: unknown, variant?: string, pointer = ''): void {
  const check = validate(schema, value, pointer)
  expect(check.ok, `${schema}${pointer} ${variant ?? ''}: ${check.text}`).toBe(true)
  if (variant && !pointer) emit(schema, variant, value)
}

/** Fails `schema` with an error at `want.instancePath` (and `want.keyword`). */
export function expectInvalid(schema: SchemaName, value: unknown, want: InvalidCase['error'], label = ''): void {
  const check = validate(schema, value)
  expect(check.ok, `${schema} ${label} must fail`).toBe(false)
  const found = check.errors.some(
    (e) => e.instancePath === want.instancePath && (want.keyword === undefined || e.keyword === want.keyword),
  )
  expect(found, `${schema} ${label}: want ${want.instancePath || '/'} ${want.keyword ?? ''}, got ${check.text}`).toBe(true)
}

/** Every invalid fixture of the contract fails for its declared reason. */
export function expectInvalidCases(schema: SchemaName, cases: InvalidCase[]): void {
  expect(cases.length, `${schema} has invalid fixtures`).toBeGreaterThan(0)
  for (const c of cases) {
    expect(c.error, `${schema} ${c.name} has an expected error`).toBeDefined()
    expectInvalid(schema, c.value, c.error, c.name)
  }
}
