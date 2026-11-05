// Well-known locations inside contracts/ and the SDK repo.

import path from 'node:path'
import { fileURLToPath } from 'node:url'

export const CONTRACTS_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
export const SDK_ROOT = path.resolve(CONTRACTS_DIR, '..')
export const SCHEMAS_DIR = path.join(CONTRACTS_DIR, 'schemas')
export const SAMPLES_DIR = path.join(CONTRACTS_DIR, 'samples')
export const FIXTURES_DIR = path.join(CONTRACTS_DIR, 'fixtures')
export const GOLDEN_DIR = path.join(CONTRACTS_DIR, 'golden')
export const REGISTRY_PATH = path.join(CONTRACTS_DIR, 'failure-codes.json')

/** Where platform factory tests emit JSON for validation: $SELLWILD_CONTRACT_OUT or contracts/out. */
export function outDir(env = process.env) {
  return env.SELLWILD_CONTRACT_OUT ? path.resolve(env.SELLWILD_CONTRACT_OUT) : path.join(CONTRACTS_DIR, 'out')
}
