// What a failure report may say about a value React Native read: its JSON
// kind (`null`, `an array`, `a string`, `an object`, ...), never the value,
// which may be listing text (contracts/FAILURES.md 7.6). The same wording as
// core's internal json-kind.ts, which the package index does not export.

export function jsonKind(value: unknown): string {
  if (value === null || value === undefined) return String(value)
  if (Array.isArray(value)) return 'an array'
  const type = typeof value
  return type === 'object' ? 'an object' : `a ${type}`
}

/**
 * A JSON.parse error cut down to its name: an Error with the same name, an
 * empty message and no stack. Engines quote part of the text they could not
 * read in the message, and that text is never sent. undefined when `error`
 * is not an Error.
 */
export function parseErrorName(error: unknown): Error | undefined {
  if (!(error instanceof Error)) return undefined
  const named = new Error('')
  named.name = error.name
  named.stack = undefined
  return named
}
