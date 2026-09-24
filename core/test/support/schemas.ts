// The contract JSON Schemas (contracts/schemas) in one Ajv 2020-12 instance,
// with the options contracts/scripts/lib/schemas.mjs uses, plus the emit step
// of contracts/README.md: factory output written to
// contracts/out/core/<schema>.<variant>.json for
// `node contracts/scripts/validate.mjs --out core`.

import Ajv2020, { type ErrorObject } from 'ajv/dist/2020'
import addFormats from 'ajv-formats'
import { contract, contractFiles } from './contracts'

export type SchemaName =
  | 'app-config'
  | 'bridge-message'
  | 'client-failure-event'
  | 'eid-blob'
  | 'events-batch'
  | 'failure-codes'
  | 'growthcode-sync-response'
  | 'listing'
  | 'listings-response'
  | 'localized-listings-config'
  | 'localized-listings-response'
  | 'rn-native-config'

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

/** Whether `errors` has one at `instancePath` (and `keyword`, when given). */
export function hasError(errors: ErrorObject[], want: { instancePath: string; keyword?: string }): boolean {
  return errors.some((e) => e.instancePath === want.instancePath && (want.keyword === undefined || e.keyword === want.keyword))
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

/** contracts/out/core, or $SELLWILD_CONTRACT_OUT/core. */
export function emitDir(): string {
  const env = (globalThis as { process?: NodeProcess }).process?.env ?? {}
  const root = env.SELLWILD_CONTRACT_OUT ?? `${CONTRACTS_DIR}out`
  return `${root.replace(/\/$/, '')}/core`
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
