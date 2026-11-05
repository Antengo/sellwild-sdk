// What a failure report may say about JSON the SDK read: the kind of a value
// (`null`, `an array`, `a string`, `an object`, ...) and the name of a parse
// error. Never the value or the text itself, so no payload reaches a failure
// report (contracts/FAILURES.md 7.6). Internal: not exported from the package
// index.

export function jsonKind(value: unknown): string {
  if (value === null || value === undefined) return String(value)
  if (Array.isArray(value)) return 'an array'
  const type = typeof value
  return type === 'object' ? 'an object' : `a ${type}`
}

/**
 * A JSON parse error cut down to its name: an Error with the same name, an
 * empty message and no stack. JSON.parse and Response.json() quote part of
 * the text they could not read in the message (V8: `Unexpected token 'I',
 * "ID5*secre"... is not valid JSON`; JSC quotes the bad token), and that text
 * is a response body or an EID blob, which are never sent. The tag-cache
 * shell uses it for encodeURIComponent's URIError too, so no engine can put
 * search keywords in the report. undefined when `error` is not an Error.
 */
export function parseErrorName(error: unknown): Error | undefined {
  if (!(error instanceof Error)) return undefined
  const named = new Error('')
  named.name = error.name
  named.stack = undefined
  return named
}
