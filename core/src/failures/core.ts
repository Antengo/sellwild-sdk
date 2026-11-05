// Pure core of logFailure (contracts/FAILURES.md sections 5–7).
//
// A TypeScript port of contracts/reference/log-failure.mjs with the same
// function names. It has no I/O, no clock and no globals: the shell in
// ./index.ts reads the flags, uid and clock, calls decideFailure, and pushes
// the event. It must reproduce contracts/golden/*.vectors.json exactly
// (test/failures-core.test.ts replays them), so change it only together with
// the reference and the vectors.
//
// Units: string lengths are Unicode code points, sizes are UTF-8 bytes, times
// are epoch milliseconds. UTF-8 is encoded by hand because TextEncoder is
// missing on Hermes before React Native 0.74.

export const CONTRACT_VERSION = '2'
export const EVENT_NAME = 'clientFailure'
export const INVALID_CODE = 'client.code.invalid'
export const UNKNOWN = 'unknown'

export const COMPONENTS = [
  'configure', 'remoteConfig', 'listings', 'localized', 'feed', 'banner', 'native',
  'video', 'house', 'bridge', 'webview', 'widget', 'shorts', 'tv', 'flipcard',
  'growthcode', 'geo', 'storage', 'sdk',
] as const
export const SEVERITIES = ['fatal', 'error', 'warn'] as const
export const CLIENTS = ['core', 'react-native', 'ios', 'android', 'flutter', 'widget'] as const
export const WRAPPERS = ['react-native', 'flutter'] as const

// Wire order of attribute keys. This is also the allowlist: nothing else is
// sent, except the call-site context keys `ctx.<key>` (CTX_KEY_RE), which
// follow these in key order.
export const ATTRIBUTE_KEYS = [
  'code', 'client', 'clientVersion', 'severity', 'fv', 'errName', 'msg', 'stack',
  'httpStatus', 'host', 'zoneId', 'wrapper', 'release',
  'appId', 'appVersion', 'os', 'device', 'slug',
  'seq', 'repeat', 'capped',
] as const

/** Call-site context keys (input.context), sent as `ctx.<key>`. */
export const CTX_KEY_RE = /^[a-z][a-zA-Z0-9_]{0,31}$/
export const CTX_PREFIX = 'ctx.'

export const LIMITS = {
  codeMax: 64,
  errName: 64,
  msg: 200,
  msgBudget: 80,
  msgKey: 64,
  stack: 4000,
  stackFrames: 30,
  frameInput: 500,
  zoneId: 32,
  host: 253,
  partnerCode: 64,
  clientVersion: 32,
  release: 64,
  appField: 64,
  ctxKeys: 8,
  ctxValue: 200,
  ctxInput: 1000,
  maxAttributes: 32,
  eventBytes: 8192,
  dedupeWindowMs: 60000,
  lruSize: 50,
  perKeyEmits: 3,
  sessionEmits: 20,
} as const

export type FailureComponent = (typeof COMPONENTS)[number]
export type FailureSeverity = (typeof SEVERITIES)[number]
export type FailureClient = (typeof CLIENTS)[number]
export type FailureWrapper = (typeof WRAPPERS)[number]
export type FailureAttributeKey = (typeof ATTRIBUTE_KEYS)[number]

/** Why decideFailure dropped a failure (null when it emitted one). */
export type FailureDropReason =
  | 'events_disabled'
  | 'failures_disabled'
  | 'sampled_out'
  | 'session_capped'
  | 'key_capped'
  | 'deduped'

/** One dedupe key. `keys` is ordered least → most recently used. */
export interface FailureKeyEntry {
  key: string
  lastEmitAt: number
  suppressed: number
  emits: number
}

export interface FailureState {
  sessionCount: number
  keys: FailureKeyEntry[]
}

/**
 * The pure-core input. Values come from call sites (and, on the widget and
 * React Native, from JS callers), so every field is checked at runtime.
 * Other fields are ignored.
 */
export interface CoreFailureInput {
  code?: unknown
  component?: unknown
  severity?: unknown
  errName?: unknown
  errMessage?: unknown
  message?: unknown
  stack?: unknown
  httpStatus?: unknown
  url?: unknown
  zoneId?: unknown
  /** Call-site context: a small map of strings and finite numbers (FAILURES.md 6.3). */
  context?: unknown
}

/** Raw context values; the core cleans and coerces every one. */
export interface CoreFailureContext {
  partnerCode?: unknown
  client?: unknown
  clientVersion?: unknown
  wrapper?: unknown
  release?: unknown
  appId?: unknown
  appVersion?: unknown
  os?: unknown
  device?: unknown
  slug?: unknown
  eventsEnabled?: unknown
  failuresEnabled?: unknown
  failuresSampleRate?: unknown
}

/** One clientFailure event, as it goes into the events queue (FAILURES.md 6.1). */
export interface ClientFailureEvent {
  event: 'clientFailure'
  action: string
  label: string
  attributes: FailureAttributes
  uid: string
  createdTime: number
}

/** The fixed attribute keys plus the call-site `ctx.<key>` keys. */
export type FailureAttributes = Partial<Record<FailureAttributeKey, string>> & { [key: `ctx.${string}`]: string }

export interface FailureDecision {
  state: FailureState
  event: ClientFailureEvent | null
  flushNow: boolean
  reason: FailureDropReason | null
}

/** Normalized fields buildFailureEvent turns into an event. */
export interface FailureFields {
  action: string
  label: string
  severity: FailureSeverity
  errName: string | null
  msg: string | null
  stack: string | null
  httpStatus: string | null
  host: string | null
  zoneId: string | null
  /** `ctx.<key>` attributes from normalizeCtx, in key order. */
  ctx?: Array<[`ctx.${string}`, string]>
  seq: number
  repeat: number
  capped: boolean
}

const CODE_RE = /^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/
const CODE_CHARS_RE = /^[a-z0-9_.]+$/
const ELLIPSIS = '…'

// ── Code points ──────────────────────────────────────────────────────────────

/** Split a string into Unicode code points (numbers). Lone surrogates stay single units. */
export function codePoints(s: string): number[] {
  const out: number[] = []
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i)
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      const d = s.charCodeAt(i + 1)
      if (d >= 0xdc00 && d <= 0xdfff) {
        out.push((c - 0xd800) * 0x400 + (d - 0xdc00) + 0x10000)
        i++
        continue
      }
    }
    out.push(c)
  }
  return out
}

function fromCodePoints(cps: number[]): string {
  let s = ''
  for (const cp of cps) s += String.fromCodePoint(cp)
  return s
}

function isLoneSurrogate(cp: number): boolean {
  return cp >= 0xd800 && cp <= 0xdfff
}

// Code points that attach to the one before them. A cut never separates them
// from their base: the base is dropped with them.
function isExtender(cp: number): boolean {
  return (cp >= 0x0300 && cp <= 0x036f) ||
    (cp >= 0x1ab0 && cp <= 0x1aff) ||
    (cp >= 0x1dc0 && cp <= 0x1dff) ||
    (cp >= 0x20d0 && cp <= 0x20ff) ||
    (cp >= 0xfe00 && cp <= 0xfe0f) ||
    (cp >= 0xfe20 && cp <= 0xfe2f) ||
    cp === 0x200d ||
    (cp >= 0x1f3fb && cp <= 0x1f3ff) ||
    (cp >= 0xe0020 && cp <= 0xe007f) ||
    (cp >= 0xe0100 && cp <= 0xe01ef)
}

function isRegionalIndicator(cp: number): boolean {
  return cp >= 0x1f1e6 && cp <= 0x1f1ff
}

/**
 * Cut `s` to at most `max` code points. When a cut happens the result ends in
 * "…", which counts toward `max`. Never splits a surrogate pair, never leaves a
 * combining mark, variation selector, skin tone, tag or ZWJ without its base,
 * and never splits a regional-indicator (flag) pair.
 */
export function truncateUnicode(s: string, max: number): string {
  const cps = codePoints(s)
  if (cps.length <= max) return s
  let k = max - 1
  while (k > 0 && (isExtender(cps[k]) || cps[k - 1] === 0x200d)) k--
  if (k > 0 && isRegionalIndicator(cps[k])) {
    let run = 0
    for (let i = k - 1; i >= 0 && isRegionalIndicator(cps[i]); i--) run++
    if (run % 2 === 1) k--
  }
  return fromCodePoints(cps.slice(0, k)) + ELLIPSIS
}

function firstCodePoints(s: string, n: number): string {
  const cps = codePoints(s)
  return cps.length <= n ? s : fromCodePoints(cps.slice(0, n))
}

// ── Text cleanup ─────────────────────────────────────────────────────────────

// Space-like code points that become U+0020 before collapsing.
function isSpaceLike(cp: number): boolean {
  return cp <= 0x1f || (cp >= 0x7f && cp <= 0x9f) || cp === 0x20 || cp === 0xa0 ||
    cp === 0x1680 || (cp >= 0x2000 && cp <= 0x200a) || cp === 0x2028 || cp === 0x2029 ||
    cp === 0x202f || cp === 0x205f || cp === 0x3000 || cp === 0xfeff
}

/**
 * Lone surrogates become U+FFFD, control and space-like code points become one
 * space, runs of spaces collapse, and the ends are trimmed.
 */
export function cleanText(s: unknown): string {
  if (typeof s !== 'string') return ''
  const out: number[] = []
  let pendingSpace = false
  for (const cp of codePoints(s)) {
    if (isSpaceLike(cp)) {
      pendingSpace = out.length > 0
      continue
    }
    if (pendingSpace) out.push(0x20)
    pendingSpace = false
    out.push(isLoneSurrogate(cp) ? 0xfffd : cp)
  }
  return fromCodePoints(out)
}

function asciiLower(s: string): string {
  return s.replace(/[A-Z]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 32))
}

function isAsciiSpace(c: string): boolean {
  return c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f' || c === '\v'
}

/** Trim U+0009–U+000D and U+0020 only (identical on every platform). */
export function trimAscii(s: string): string {
  let a = 0
  let b = s.length
  while (a < b && isAsciiSpace(s[a])) a++
  while (b > a && isAsciiSpace(s[b - 1])) b--
  return s.slice(a, b)
}

// ── Host extraction ──────────────────────────────────────────────────────────

const SCHEME_RE = /^[A-Za-z][A-Za-z0-9+.-]*$/
const IPV4_RE = /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$/
const HOST_PUNCT = ".-_~%!$&'*+,;=:@[]"

function isAuthorityChar(ch: string): boolean {
  const cp = ch.codePointAt(0) as number
  if (cp >= 0x80) return true
  if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) return true
  return HOST_PUNCT.includes(ch)
}

/**
 * Hostname of an absolute (`scheme://`) or protocol-relative (`//`) URL, lower
 * case, without userinfo, port or trailing dots. IP literals become "<ip>".
 * Returns null when there is no host.
 */
export function hostOf(url: unknown): string | null {
  if (typeof url !== 'string') return null
  const s = trimAscii(url)
  let rest: string
  const i = s.indexOf('://')
  if (i > 0 && SCHEME_RE.test(s.slice(0, i))) rest = s.slice(i + 3)
  else if (s.startsWith('//')) rest = s.slice(2)
  else return null
  let auth = ''
  for (const ch of rest) {
    if (ch === '/' || ch === '?' || ch === '#' || !isAuthorityChar(ch)) break
    auth += ch
  }
  const at = auth.lastIndexOf('@')
  if (at >= 0) auth = auth.slice(at + 1)
  if (auth.startsWith('[')) return auth.includes(']') ? '<ip>' : null
  const colon = auth.indexOf(':')
  if (colon >= 0) auth = auth.slice(0, colon)
  while (auth.endsWith('.')) auth = auth.slice(0, -1)
  const host = asciiLower(auth)
  if (host === '') return null
  if (IPV4_RE.test(host)) return '<ip>'
  return host
}

// ── Message and stack sanitizing ─────────────────────────────────────────────

// One left-to-right pass; the first alternative that matches at a position wins
// and replaced text is never scanned again.
const URL_ALT = '([A-Za-z][A-Za-z0-9+.-]*://[^ "\'<>()]*)'
const PROTO_REL_ALT = '(//[A-Za-z0-9-]+\\.[^ "\'<>()]*)'
const EMAIL_ALT = '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,})'
// React Native JavaScriptCore frame `name@<file>.bundle` or `name@<file>.jsbundle`,
// optionally with `:line` or `:line:col`. Stacks only, tried before the email
// alternative so the frame is kept; `.bundle` must end the host-like run, so
// `x@evil.com.bundle.example.com` is still an email.
const JSC_FRAME_ALT = '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.(?:js)?bundle(?![A-Za-z0-9.-])(?::[0-9]+){0,2})'
const UUID_ALT = '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})'
const IPV4_ALT = '([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3})'
const DIGITS_ALT = '([0-9]{6,})'
const PATH_ALT = '([^ ():]*/)'
const QUERY_ALT = '(\\?[^ :()]*)'

export const MESSAGE_PATTERN = [URL_ALT, PROTO_REL_ALT, EMAIL_ALT, UUID_ALT, IPV4_ALT, DIGITS_ALT].join('|')
export const FRAME_PATTERN = [URL_ALT, PROTO_REL_ALT, JSC_FRAME_ALT, EMAIL_ALT, UUID_ALT, IPV4_ALT, PATH_ALT, QUERY_ALT].join('|')

const MESSAGE_RE = new RegExp(MESSAGE_PATTERN, 'g')
const FRAME_RE = new RegExp(FRAME_PATTERN, 'g')

type Group = string | undefined

/**
 * PII-safe message: cleanText, then URLs → host (or "<url>"), emails →
 * "<email>", UUIDs → "<id>", IPv4 → "<ip>", 6+ digit runs → "<n>".
 * Not truncated here.
 */
export function sanitizeMessage(s: unknown): string {
  const text = cleanText(s)
  return text.replace(MESSAGE_RE, (m: string, url: Group, rel: Group, email: Group, uuid: Group, ip: Group) => {
    if (url !== undefined || rel !== undefined) return hostOf(m) ?? '<url>'
    if (email !== undefined) return '<email>'
    if (uuid !== undefined) return '<id>'
    if (ip !== undefined) return '<ip>'
    return '<n>'
  })
}

function basenameOfUrl(u: string): string {
  const cut = u.search(/[?#]/)
  const path = cut >= 0 ? u.slice(0, cut) : u
  // A URL or protocol-relative match always holds a "/" before any ? or #,
  // as in the reference (contracts/reference/log-failure.mjs).
  return path.slice(path.lastIndexOf('/') + 1)
}

/** Hosts whose stack URLs are kept whole, so their frames can be source-mapped. */
export const OUR_DOMAINS: readonly string[] = ['sellwild.com', 'sellwild.org']

/** True for sellwild.com, sellwild.org and any subdomain of either. */
export function isOurHost(host: string): boolean {
  return OUR_DOMAINS.some((d) => host === d || host.endsWith('.' + d))
}

const LINE_COL_RE = /(:[0-9]+){1,2}$/
const PATH_PII_RE = new RegExp([EMAIL_ALT, UUID_ALT, IPV4_ALT].join('|'), 'g')

/**
 * A stack URL on one of our hosts (FAILURES.md 7.4): the scheme (lower case)
 * or "//", the host from hostOf, the path, then the trailing ":line" or
 * ":line:col". Userinfo, port, query and fragment are removed; emails, UUIDs
 * and IPv4s in the path are masked.
 */
function keepOurUrl(m: string, host: string): string {
  const prefix = m.startsWith('//') ? '//' : asciiLower(m.slice(0, m.indexOf('://'))) + '://'
  const rest = m.slice(prefix.length)
  let auth = ''
  for (const ch of rest) {
    if (ch === '/' || ch === '?' || ch === '#' || !isAuthorityChar(ch)) break
    auth += ch
  }
  const after = rest.slice(auth.length)
  const lc = after.match(LINE_COL_RE)?.[0] ?? ''
  const pathAndQuery = after.slice(0, after.length - lc.length)
  const cut = pathAndQuery.search(/[?#]/)
  const path = (cut >= 0 ? pathAndQuery.slice(0, cut) : pathAndQuery)
    .replace(PATH_PII_RE, (_m: string, email: Group, uuid: Group) =>
      email !== undefined ? '<email>' : uuid !== undefined ? '<id>' : '<ip>')
  return prefix + host + path + lc
}

function sanitizeFrame(line: string): string {
  const text = cleanText(line)
  return text.replace(FRAME_RE, (m: string, url: Group, rel: Group, jsc: Group, email: Group, uuid: Group, ip: Group) => {
    if (url !== undefined || rel !== undefined) {
      const host = hostOf(m)
      if (host !== null) return isOurHost(host) ? keepOurUrl(m, host) : host
      const base = basenameOfUrl(m)
      return base === '' ? '<url>' : base
    }
    if (jsc !== undefined) return m
    if (email !== undefined) return '<email>'
    if (uuid !== undefined) return '<id>'
    if (ip !== undefined) return '<ip>'
    return ''
  })
}

/**
 * First 30 frames of a stack, one per line: the engine header line
 * (`errName` or `errName: …`) is dropped, each frame is cut to its first 500
 * UTF-16 units (so the patterns never see a long line), URLs on our hosts
 * keep their path and line:col (no query), other URLs become hosts,
 * directories and query strings are removed, emails/UUIDs/IPs are masked.
 * Max 4000 code points. Returns null when nothing is left.
 */
export function sanitizeStack(stack: unknown, errName: string | null): string | null {
  if (typeof stack !== 'string') return null
  let lines = stack.split('\n').map((l) => trimAscii(l.replace(/\r/g, ''))).filter((l) => l !== '')
  if (errName && lines.length > 0 && (lines[0] === errName || lines[0].startsWith(errName + ':'))) {
    lines = lines.slice(1)
  }
  const frames = lines.slice(0, LIMITS.stackFrames)
    .map((l) => sanitizeFrame(capInput(l, LIMITS.frameInput) as string))
    .filter((l) => l !== '')
  if (frames.length === 0) return null
  return truncateUnicode(frames.join('\n'), LIMITS.stack)
}

// ── Field normalizers ────────────────────────────────────────────────────────

/** A code that fails the registry format becomes "client.code.invalid". */
export function normalizeCode(code: unknown): string {
  if (typeof code !== 'string' || code.length > LIMITS.codeMax) return INVALID_CODE
  if (!CODE_CHARS_RE.test(code) || !CODE_RE.test(code)) return INVALID_CODE
  return code
}

/** Exact match against the component enum, else "unknown". */
export function normalizeComponent(component: unknown): string {
  return typeof component === 'string' && (COMPONENTS as readonly string[]).includes(component) ? component : UNKNOWN
}

/** Exact match against fatal | error | warn, else "error". */
export function normalizeSeverity(severity: unknown): FailureSeverity {
  return typeof severity === 'string' && (SEVERITIES as readonly string[]).includes(severity)
    ? (severity as FailureSeverity)
    : 'error'
}

/** HTTP status as exactly three digits, else null. */
export function normalizeHttpStatus(v: unknown): string | null {
  if (typeof v === 'number') {
    return Number.isInteger(v) && v >= 100 && v <= 999 ? String(v) : null
  }
  if (typeof v === 'string') {
    const t = trimAscii(v)
    return /^[0-9]{3}$/.test(t) ? t : null
  }
  return null
}

/** Integer numbers or strings; cleaned and cut to 32 code points. */
export function normalizeZoneId(v: unknown): string | null {
  let s: string | null = null
  if (typeof v === 'number') {
    if (Number.isSafeInteger(v)) s = String(v)
  } else if (typeof v === 'string') {
    s = v
  }
  if (s === null) return null
  const t = cleanText(s)
  return t === '' ? null : truncateUnicode(t, LIMITS.zoneId)
}

/** The first `max` UTF-16 units of a string; anything else unchanged (FAILURES.md 3.3 item 4). */
export function capInput(v: unknown, max: number): unknown {
  return typeof v === 'string' && v.length > max ? v.slice(0, max) : v
}

/** Up to 6 decimals, trailing zeros and a bare point removed; "-0" → "0". */
export function formatDecimal(v: number): string {
  const s = v.toFixed(6).replace(/0+$/, '').replace(/\.$/, '')
  return s === '-0' ? '0' : s
}

/**
 * A call-site context value as text: a string is cut to 1000 UTF-16 units and
 * sanitized like msg (7.5); a safe integer is written in decimal; another
 * finite number with |v| < 1e15 is written with up to 6 decimals. Cut to 200
 * code points. Anything else, or empty, → null.
 */
export function normalizeCtxValue(v: unknown): string | null {
  let s: string | null = null
  if (typeof v === 'string') {
    s = sanitizeMessage(capInput(v, LIMITS.ctxInput))
  } else if (typeof v === 'number' && Number.isFinite(v)) {
    if (Number.isSafeInteger(v)) s = String(v)
    else if (Math.abs(v) < 1e15) s = formatDecimal(v)
  }
  if (s === null || s === '') return null
  return truncateUnicode(s, LIMITS.ctxValue)
}

/**
 * The call-site context as attributes: keys matching CTX_KEY_RE whose value
 * normalizes to text, sorted by key, the first 8 kept, each as `ctx.<key>`.
 * Anything that is not a plain object → none.
 */
export function normalizeCtx(context: unknown): Array<[`ctx.${string}`, string]> {
  if (context === null || typeof context !== 'object' || Array.isArray(context)) return []
  const map = context as Record<string, unknown>
  const out: Array<[`ctx.${string}`, string]> = []
  for (const k of Object.keys(map).filter((key) => CTX_KEY_RE.test(key)).sort()) {
    if (out.length === LIMITS.ctxKeys) break
    const v = normalizeCtxValue(map[k])
    if (v !== null) out.push([`${CTX_PREFIX}${k}`, v])
  }
  return out
}

function cleanBounded(v: unknown, max: number): string | null {
  if (typeof v !== 'string') return null
  const t = cleanText(v)
  return t === '' ? null : truncateUnicode(t, max)
}

// ── Flags and sampling ───────────────────────────────────────────────────────

const FALSE_WORDS = ['false', '0', 'no', 'off']

/**
 * Kill-switch coercion: boolean as is; number → value != 0; string → not one
 * of false/0/no/off after ASCII trim and ASCII lower case; anything else
 * (null, absent, object, array) → `dflt`.
 */
export function coerceFlag(v: unknown, dflt = true): boolean {
  if (typeof v === 'boolean') return v
  if (typeof v === 'number') return v !== 0
  if (typeof v === 'string') return !FALSE_WORDS.includes(asciiLower(trimAscii(v)))
  return dflt
}

const RATE_RE = /^\+?([0-9]+(\.[0-9]*)?|\.[0-9]+)$/

/**
 * FAILURES_SAMPLE_RATE: a finite number, or a plain decimal string, clamped to
 * [0, 1]. Anything else (null, '', NaN, '50%', booleans, objects) → 1.
 */
export function coerceRate(v: unknown): number {
  const n = parseRate(v)
  if (n === null) return 1
  return Math.min(1, Math.max(0, n))
}

/**
 * The number a FAILURES_SAMPLE_RATE value names, before clamping: a finite
 * number, or a plain decimal string. null when it names none, which
 * coerceRate reads as 1.
 */
export function parseRate(v: unknown): number | null {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null
  if (typeof v === 'string') {
    const t = trimAscii(v)
    if (RATE_RE.test(t)) return Number(t)
  }
  return null
}

// UTF-8 byte count of one code point. A lone surrogate counts as U+FFFD
// (3 bytes), as TextEncoder encodes it.
function utf8Length(cp: number): number {
  if (cp < 0x80) return 1
  if (cp < 0x800) return 2
  if (cp < 0x10000) return 3
  return 4
}

function utf8Bytes(cp: number): number[] {
  if (cp < 0x80) return [cp]
  if (cp < 0x800) return [0xc0 | (cp >> 6), 0x80 | (cp & 0x3f)]
  if (cp < 0x10000) return [0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f)]
  return [0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f)]
}

/** FNV-1a 32-bit over the UTF-8 bytes of `s`, as an unsigned integer. */
export function fnv1a32(s: unknown): number {
  let h = 0x811c9dc5
  for (const cp of codePoints(typeof s === 'string' ? s : '')) {
    for (const b of utf8Bytes(isLoneSurrogate(cp) ? 0xfffd : cp)) {
      h ^= b
      h = Math.imul(h, 0x01000193) >>> 0
    }
  }
  return h >>> 0
}

/** Session sampling: fnv1a32(uid + ":failures") / 2^32 < rate. */
export function isSampled(uid: unknown, rate: number): boolean {
  if (rate >= 1) return true
  if (rate <= 0) return false
  const u = typeof uid === 'string' ? uid : ''
  return fnv1a32(u + ':failures') / 4294967296 < rate
}

// ── Dedupe ───────────────────────────────────────────────────────────────────

/** action|label|errName|first 64 code points of the sanitized (uncut) message. */
export function dedupeKey(action: string, label: string, errName: string | null, msgFull: string | null): string {
  return [action, label, errName ?? '', firstCodePoints(msgFull ?? '', LIMITS.msgKey)].join('|')
}

export function initialState(): FailureState {
  return { sessionCount: 0, keys: [] }
}

/**
 * The full sanitized message before the 200 cut (FAILURES.md 7.5): the
 * non-empty of message and error message, joined with ": ", the error message
 * left out when it equals the message.
 */
export function messageFull(input: CoreFailureInput): string {
  const fromMessage = typeof input.message === 'string' ? sanitizeMessage(input.message) : ''
  const fromError = typeof input.errMessage === 'string' ? sanitizeMessage(input.errMessage) : ''
  const parts = [fromMessage]
  if (fromError !== fromMessage) parts.push(fromError)
  return parts.filter((p) => p !== '').join(': ')
}

// ── Event building ───────────────────────────────────────────────────────────

function jsonString(s: string): string {
  let out = '"'
  for (const ch of s) {
    const c = ch.charCodeAt(0)
    if (ch === '"') out += '\\"'
    else if (ch === '\\') out += '\\\\'
    else if (c === 0x08) out += '\\b'
    else if (c === 0x0c) out += '\\f'
    else if (c === 0x0a) out += '\\n'
    else if (c === 0x0d) out += '\\r'
    else if (c === 0x09) out += '\\t'
    else if (c < 0x20) out += '\\u' + c.toString(16).padStart(4, '0')
    else out += ch
  }
  return out + '"'
}

/**
 * Canonical JSON of the event (fixed key order, no whitespace, minimal
 * escaping, "/" and non-ASCII left literal). Its UTF-8 length is the size the
 * 8192-byte budget is measured against.
 */
export function canonicalJson(event: ClientFailureEvent): string {
  const attributes = event.attributes as Record<string, string | undefined>
  const ctxKeys = Object.keys(attributes).filter((k) => k.startsWith(CTX_PREFIX)).sort()
  const attrs = [...ATTRIBUTE_KEYS.filter((k) => attributes[k] !== undefined), ...ctxKeys]
    .map((k) => jsonString(k) + ':' + jsonString(attributes[k] as string))
    .join(',')
  return '{"event":' + jsonString(event.event) +
    ',"action":' + jsonString(event.action) +
    ',"label":' + jsonString(event.label) +
    ',"attributes":{' + attrs + '}' +
    ',"uid":' + jsonString(event.uid) +
    ',"createdTime":' + String(event.createdTime) + '}'
}

export function eventByteSize(event: ClientFailureEvent): number {
  let n = 0
  for (const cp of codePoints(canonicalJson(event))) n += utf8Length(cp)
  return n
}

/**
 * Build the wire event from normalized fields and apply the size budget:
 * over 8192 bytes → drop every ctx.* key; still over → drop stack; still over
 * → cut msg to 80; still over → drop msg; still over → send as is.
 */
export function buildFailureEvent(
  fields: FailureFields,
  context: CoreFailureContext | null | undefined,
  uid: unknown,
  now: number,
): ClientFailureEvent {
  const ctx = context ?? {}
  const a: Record<FailureAttributeKey, string | undefined> = {
    code: cleanBounded(ctx.partnerCode, LIMITS.partnerCode) ?? UNKNOWN,
    client: typeof ctx.client === 'string' && ctx.client !== '' ? ctx.client : UNKNOWN,
    clientVersion: cleanBounded(ctx.clientVersion, LIMITS.clientVersion) ?? UNKNOWN,
    severity: fields.severity,
    fv: CONTRACT_VERSION,
    errName: fields.errName ?? undefined,
    msg: fields.msg ?? undefined,
    stack: fields.stack ?? undefined,
    httpStatus: fields.httpStatus ?? undefined,
    host: fields.host ?? undefined,
    zoneId: fields.zoneId ?? undefined,
    wrapper: (WRAPPERS as readonly unknown[]).includes(ctx.wrapper) ? (ctx.wrapper as string) : undefined,
    release: cleanBounded(ctx.release, LIMITS.release) ?? undefined,
    appId: cleanBounded(ctx.appId, LIMITS.appField) ?? undefined,
    appVersion: cleanBounded(ctx.appVersion, LIMITS.appField) ?? undefined,
    os: cleanBounded(ctx.os, LIMITS.appField) ?? undefined,
    device: cleanBounded(ctx.device, LIMITS.appField) ?? undefined,
    slug: cleanBounded(ctx.slug, LIMITS.appField) ?? undefined,
    seq: String(fields.seq),
    repeat: String(fields.repeat),
    capped: fields.capped ? '1' : undefined,
  }
  const attributes: FailureAttributes = {}
  for (const k of ATTRIBUTE_KEYS) if (a[k] !== undefined) attributes[k] = a[k]
  for (const [k, v] of fields.ctx ?? []) attributes[k] = v
  const event: ClientFailureEvent = {
    event: EVENT_NAME,
    action: fields.action,
    label: fields.label,
    attributes,
    uid: typeof uid === 'string' ? uid : '',
    createdTime: now,
  }
  if (eventByteSize(event) > LIMITS.eventBytes) {
    for (const k of Object.keys(attributes)) if (k.startsWith(CTX_PREFIX)) delete attributes[k as `ctx.${string}`]
  }
  if (eventByteSize(event) > LIMITS.eventBytes && attributes.stack !== undefined) delete attributes.stack
  if (eventByteSize(event) > LIMITS.eventBytes && attributes.msg !== undefined) {
    attributes.msg = truncateUnicode(attributes.msg, LIMITS.msgBudget)
  }
  if (eventByteSize(event) > LIMITS.eventBytes && attributes.msg !== undefined) delete attributes.msg
  return event
}

// ── The gate ─────────────────────────────────────────────────────────────────

function touch(keys: FailureKeyEntry[], entry: FailureKeyEntry): FailureKeyEntry[] {
  return [...keys.filter((e) => e.key !== entry.key), entry]
}

/**
 * The whole decision as a pure function.
 *
 * input:   { code, component, severity?, errName?, errMessage?, message?, stack?,
 *            httpStatus?, url?, zoneId?, context? }  (other fields are ignored)
 * context: { partnerCode, client, clientVersion, wrapper?, release?,
 *            appId?, appVersion?, os?, device?, slug?,
 *            eventsEnabled?, failuresEnabled?, failuresSampleRate? }
 * state:   { sessionCount, keys: [{ key, lastEmitAt, suppressed, emits }] }
 *          keys are ordered least → most recently used.
 *
 * Returns { state, event, flushNow, reason }. `event` is null when dropped and
 * `reason` names the gate that dropped it (null when emitted).
 */
export function decideFailure(
  state: FailureState | null | undefined,
  input: CoreFailureInput | null | undefined,
  context: CoreFailureContext | null | undefined,
  uid: unknown,
  now: number,
): FailureDecision {
  const st = state ?? initialState()
  const ctx = context ?? {}
  const inp = input ?? {}
  const drop = (reason: FailureDropReason, next: FailureState = st): FailureDecision =>
    ({ state: next, event: null, flushNow: false, reason })

  if (!coerceFlag(ctx.eventsEnabled, true)) return drop('events_disabled')
  if (!coerceFlag(ctx.failuresEnabled, true)) return drop('failures_disabled')

  const action = normalizeCode(inp.code)
  const label = normalizeComponent(inp.component)
  const severity = normalizeSeverity(inp.severity)

  if (severity !== 'fatal' && !isSampled(uid, coerceRate(ctx.failuresSampleRate))) {
    return drop('sampled_out')
  }
  if (st.sessionCount >= LIMITS.sessionEmits) return drop('session_capped')

  const errName = cleanBounded(inp.errName, LIMITS.errName)
  const msgFull = messageFull(inp)

  const key = dedupeKey(action, label, errName, msgFull)
  const existing = st.keys.find((e) => e.key === key)
  if (existing) {
    if (existing.emits >= LIMITS.perKeyEmits) {
      return drop('key_capped', { ...st, keys: touch(st.keys, { ...existing }) })
    }
    if (now - existing.lastEmitAt < LIMITS.dedupeWindowMs) {
      const bumped = { ...existing, suppressed: existing.suppressed + 1 }
      return drop('deduped', { ...st, keys: touch(st.keys, bumped) })
    }
  }

  const seq = st.sessionCount + 1
  const repeat = (existing ? existing.suppressed : 0) + 1
  const entry = { key, lastEmitAt: now, suppressed: 0, emits: (existing ? existing.emits : 0) + 1 }
  let keys = touch(st.keys, entry)
  if (keys.length > LIMITS.lruSize) keys = keys.slice(keys.length - LIMITS.lruSize)

  const host = hostOf(inp.url)
  const event = buildFailureEvent({
    action,
    label,
    severity,
    errName,
    msg: msgFull === '' ? null : truncateUnicode(msgFull, LIMITS.msg),
    stack: sanitizeStack(inp.stack, errName),
    httpStatus: normalizeHttpStatus(inp.httpStatus),
    host: host === null ? null : truncateUnicode(host, LIMITS.host),
    zoneId: normalizeZoneId(inp.zoneId),
    ctx: normalizeCtx(inp.context),
    seq,
    repeat,
    capped: seq === LIMITS.sessionEmits,
  }, ctx, uid, now)

  return {
    state: { sessionCount: seq, keys },
    event,
    flushNow: seq === 1 || severity === 'fatal',
    reason: null,
  }
}
