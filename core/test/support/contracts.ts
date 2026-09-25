// Read-only access to the shared contracts (../../../contracts): samples,
// fixtures, schemas, expectations and golden vectors, loaded as JSON by vite
// at test time. Callers get a fresh copy, so a test can change what it gets.
//
// Paths are relative to contracts/, e.g. 'fixtures/listing/valid/numeric-id.json'.

const PREFIX = '../../../contracts/'

const files = import.meta.glob<unknown>(
  [
    '../../../contracts/samples/**/*.json',
    '../../../contracts/fixtures/**/*.json',
    '../../../contracts/schemas/*.json',
    '../../../contracts/expectations/*.json',
    '../../../contracts/expectations/drift/*.json',
    '../../../contracts/golden/*.json',
    '../../../contracts/failure-codes.json',
  ],
  { eager: true, import: 'default' },
)

const byPath = new Map(Object.entries(files).map(([key, value]) => [key.slice(PREFIX.length), value]))

/** A fresh copy of one contracts JSON file. Throws when it does not exist. */
export function contract<T = unknown>(path: string): T {
  if (!byPath.has(path)) throw new Error(`no contracts file ${path}`)
  return structuredClone(byPath.get(path)) as T
}

/** File names (not paths) of the JSON files directly in a contracts folder, sorted, `_*` left out. */
export function contractFiles(dir: string): string[] {
  const prefix = dir.endsWith('/') ? dir : `${dir}/`
  return [...byPath.keys()]
    .filter((p) => p.startsWith(prefix) && !p.slice(prefix.length).includes('/'))
    .map((p) => p.slice(prefix.length))
    .filter((name) => !name.startsWith('_'))
    .sort()
}

/** Drop the `_synthetic` fixture marker: it is never on the wire. */
export function withoutMarker<T>(value: T): T {
  if (Array.isArray(value)) return value.map((v) => withoutMarker(v)) as T
  if (value && typeof value === 'object') {
    const { _synthetic, ...rest } = value as Record<string, unknown>
    return rest as T
  }
  return value
}

/** The variant name of a fixture or sample file: its name without `.json`. */
export function variantName(file: string): string {
  return file.replace(/\.json$/, '')
}
