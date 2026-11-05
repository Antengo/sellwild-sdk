// Assertions the factory tests share: a value passes a contract schema (and
// is emitted for validate.mjs), or fails it for the reason the contract names.

import { expect } from 'vitest'
import type { InvalidCase } from '../factories'
import { emit, hasError, validate, type SchemaName } from './schemas'

/** Passes `schema` (or a `#/$defs` pointer in it). With `variant`, also emitted to contracts/out/core. */
export function expectValid(schema: SchemaName, value: unknown, variant?: string, pointer = ''): void {
  const check = validate(schema, value, pointer)
  expect(check.ok, `${schema}${pointer} ${variant ?? ''}: ${check.text}`).toBe(true)
  if (variant && !pointer) emit(schema, variant, value)
}

/** Fails `schema` with an error at `want.instancePath` (and `want.keyword`). */
export function expectInvalid(schema: SchemaName, value: unknown, want: InvalidCase['error'], label = ''): void {
  const check = validate(schema, value)
  expect(check.ok, `${schema} ${label} must fail`).toBe(false)
  expect(hasError(check.errors, want), `${schema} ${label}: want ${want.instancePath || '/'} ${want.keyword ?? ''}, got ${check.text}`).toBe(true)
}

/** Every invalid fixture of the contract fails for its declared reason. */
export function expectInvalidCases(schema: SchemaName, cases: InvalidCase[]): void {
  expect(cases.length, `${schema} has invalid fixtures`).toBeGreaterThan(0)
  for (const c of cases) {
    expect(c.error, `${schema} ${c.name} has an expected error`).toBeDefined()
    expectInvalid(schema, c.value, c.error, c.name)
  }
}
