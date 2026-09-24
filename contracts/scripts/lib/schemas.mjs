// Loads every contracts/schemas/*.schema.json into one Ajv 2020-12 instance.

import fs from 'node:fs'
import path from 'node:path'
import Ajv2020 from 'ajv/dist/2020.js'
import addFormats from 'ajv-formats'
import { SCHEMAS_DIR } from './paths.mjs'

export function schemaNames(dir = SCHEMAS_DIR) {
  return fs.readdirSync(dir).filter((f) => f.endsWith('.schema.json')).map((f) => f.replace(/\.schema\.json$/, '')).sort()
}

export function readSchema(name, dir = SCHEMAS_DIR) {
  return JSON.parse(fs.readFileSync(path.join(dir, `${name}.schema.json`), 'utf8'))
}

/**
 * Returns { ajv, validators, errors } where validators maps schema name to a
 * compiled function and errors maps schema name to its compile error text.
 */
export function loadSchemas(dir = SCHEMAS_DIR) {
  const ajv = new Ajv2020({ allErrors: true, strict: true, allowUnionTypes: true })
  addFormats(ajv)
  const names = schemaNames(dir)
  const docs = Object.fromEntries(names.map((n) => [n, readSchema(n, dir)]))
  for (const n of names) ajv.addSchema(docs[n])
  const validators = {}
  const errors = {}
  for (const n of names) {
    try {
      validators[n] = ajv.getSchema(docs[n].$id)
      if (!validators[n]) throw new Error(`no schema registered for ${docs[n].$id}`)
    } catch (e) {
      errors[n] = e.message
    }
  }
  return { ajv, validators, errors, docs }
}

/** Short, stable text for ajv errors. */
export function formatErrors(errs, max = 3) {
  return (errs ?? []).slice(0, max).map((e) => `${e.instancePath || '/'} ${e.keyword}: ${e.message}`).join('; ')
}
