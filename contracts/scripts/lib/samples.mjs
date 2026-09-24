// Shared sample bookkeeping for scripts/refresh-samples.mjs and the tests:
// the list of real payloads, the base64 truncation rule and SOURCES.json.

import crypto from 'node:crypto'

export const FETCHED_AT = '2026-09-23'

/**
 * Every committed real sample. `url` is the GET that produced it. Samples that
 * are not refreshable were captured another way (`source`) or live on a host
 * outside the refresh allowlist.
 */
export const SAMPLE_SPECS = [
  { file: 'app-config/weatherbug_weatherbug-weatherbug.json', url: 'https://widget.sellwild.com/app/weatherbug/weatherbug-weatherbug.json', status: 200 },
  { file: 'app-config/antengo_antengo-sellwild-tv.json', url: 'https://widget.sellwild.com/app/antengo/antengo-sellwild-tv.json', status: 200 },
  { file: 'app-config/realgm_realgm-realgm.403.xml', url: 'https://widget.sellwild.com/app/realgm/realgm-realgm.json', status: 403, note: 'Missing config: S3 answers 403 AccessDenied XML, not 404.' },
  { file: 'app-config/weatherbug_weatherbug-main.403.xml', url: 'https://widget.sellwild.com/app/weatherbug/weatherbug-main.json', status: 403, note: 'Missing config: S3 answers 403 AccessDenied XML, not 404.' },
  {
    file: 'app-config/weatherbug_weatherbug-weatherbug.local-build.json',
    url: null,
    source: 'sellwild-widget scripts/escompile.mjs buildApp() run in memory on app/weatherbug-weatherbug.md at HEAD',
    status: null,
    refreshable: false,
    note: 'Producer output; equal to the CDN file key for key.',
  },
  {
    file: 'app-config/antengo_antengo-sellwild-tv.local-build.json',
    url: null,
    source: 'sellwild-widget scripts/escompile.mjs buildApp() run in memory on app/antengo-sellwild-tv.md at HEAD',
    status: null,
    refreshable: false,
    note: 'Producer output; equal to the CDN file key for key.',
  },
  { file: 'listings-response/listings-img-data-sm.json', url: 'https://cache.sellwild.com/listings-img-data-sm', status: 200 },
  { file: 'listings-response/listings-img-data-sm.headers.txt', url: 'https://cache.sellwild.com/listings-img-data-sm', status: 200, kind: 'headers' },
  { file: 'listings-response/listings-img-data-sm-avif-weatherbug.json', url: 'https://cache.sellwild.com/listings-img-data-sm-avif-weatherbug', status: 200 },
  { file: 'listings-response/listings-img-data-sm-avif-weatherbug.headers.txt', url: 'https://cache.sellwild.com/listings-img-data-sm-avif-weatherbug', status: 200, kind: 'headers' },
  { file: 'listings-response/bargainhunter.json', url: 'https://cache.sellwild.com/bargainhunter', status: 200 },
  { file: 'listings-response/listings-sm.json', url: 'https://cache.sellwild.com/listings-sm', status: 200 },
  {
    file: 'listings-response/s3-sellwild-cache-listings-sm.json',
    url: 'https://s3.amazonaws.com/sellwild-cache/listings-sm',
    status: 200,
    refreshable: false,
    note: 'Legacy web-only S3 cache (host is outside the refresh allowlist).',
  },
  { file: 'localized-listings-response/sports-img-data-sm-webp-al.json', url: 'https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-al.json', status: 200 },
  { file: 'localized-listings-response/sports-img-data-sm-webp-ga.json', url: 'https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-ga.json', status: 200 },
  { file: 'localized-listings-response/sports-img-data-sm-webp-zz.403.xml', url: 'https://sellwild-sports-cache.s3.us-east-1.amazonaws.com/sports-img-data-sm-webp-zz.json', status: 403, note: 'Unknown state: 403 AccessDenied XML (code comments say 404).' },
]

export const BASE64_STUB_CHARS = 16
const DATA_URI_RE = /^(data:image\/[a-z0-9.+-]+;base64,)([A-Za-z0-9+/=]*)$/

export function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex')
}

/**
 * Cut every inline base64 image to a 16-character stub (still valid base64),
 * keeping the data:image/<type>;base64, prefix. Returns { value, truncated }.
 */
export function truncateDataUris(value) {
  let truncated = false
  const walk = (v) => {
    if (typeof v === 'string') {
      const m = DATA_URI_RE.exec(v)
      if (m && m[2].length > BASE64_STUB_CHARS) {
        truncated = true
        return m[1] + m[2].slice(0, BASE64_STUB_CHARS)
      }
      return v
    }
    if (Array.isArray(v)) return v.map(walk)
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, walk(x)]))
    return v
  }
  return { value: walk(value), truncated }
}

/**
 * Bytes to commit for one captured body, plus its SOURCES.json entry. JSON
 * bodies with inline images are re-serialized after truncation; everything
 * else is committed byte for byte.
 */
export function prepareSample(spec, originalBytes, fetchedAt = FETCHED_AT) {
  const buf = Buffer.from(originalBytes)
  let out = buf
  let truncated = false
  if (spec.file.endsWith('.json')) {
    const parsed = JSON.parse(buf.toString('utf8'))
    const r = truncateDataUris(parsed)
    if (r.truncated) {
      truncated = true
      out = Buffer.from(JSON.stringify(r.value, null, 2) + '\n')
    }
  }
  const entry = {
    file: spec.file,
    url: spec.url,
    method: spec.url ? 'GET' : null,
    status: spec.status,
    fetchedAt,
    sha256: sha256(buf),
    bytes: buf.length,
    truncated,
    refreshable: spec.refreshable !== false,
  }
  if (spec.kind) entry.kind = spec.kind
  if (spec.source) entry.source = spec.source
  if (spec.note) entry.note = spec.note
  return { bytes: out, entry }
}

export function sourcesDocument(entries) {
  return {
    description: 'Real payloads captured with read-only GETs. sha256 and bytes describe the ORIGINAL response body; when truncated is true the committed file has its base64 images cut to a 16-character stub. Refresh with CONTRACTS_LIVE=1 node scripts/refresh-samples.mjs.',
    samples: entries,
  }
}
