// growthcode.ts — GrowthCode Signal Resolve (identity) core logic.
//
// GrowthCode is an identity provider. The SDK POSTs a "sync" to GrowthCode
// with (optionally) the device advertising id and a stored GCID; GrowthCode
// returns a GCID to persist and an EID blob to merge into the Prebid auction.
//
// This module is the PLATFORM-NEUTRAL reference: request/response shapes, the
// EID-blob parser, the consumer-wins merge, the sync throttle, and the
// local→remote→default settings resolution. It does no network, storage or
// device-id access of its own. The native SDKs (iOS/Android) mirror these
// functions with their own HTTP/persistence/advertising-id adapters, and a
// future web build can call these directly.
//
// Failures (contracts/FAILURES.md): the `*WithIssues` functions, like
// shouldSync, mergeEids and the builders, are pure and return what went wrong
// next to their result. The plain resolveGrowthCode, parseEidBlob and
// parseGrowthCodeResponse are thin shells over them that report each issue
// once with logFailure (growthcode.config.missing, growthcode.eid.parse,
// growthcode.eid.invalid, growthcode.sync.invalid), which queues an events
// POST, and return the same result as always.
//
// API contract (GrowthCode Signal Resolve v1.0, direct API):
//   POST {endpoint}?pid={partnerId}&u={syncUrl}
//   Content-Type: application/x-www-form-urlencoded
//   body: gcid, h, ref, h1 (HEM md5), h3 (HEM sha256), maid, maid_type
// Response JSON: gc_id, eb (serialized EID blob), idi, version, plus web-only
// directives (cookies/kv/dl/ls, bucket, gctest, persistent) the SDK ignores.

import type { SellwildEid, SellwildEidUid, SellwildConfig, GrowthCodeConfig } from './types'
import { logFailure, type LogFailureInput } from './failures'
import { jsonKind, parseErrorName } from './json-kind'

/** Default GrowthCode sync endpoint (overridable via GROWTHCODE_ENDPOINT). */
export const GROWTHCODE_DEFAULT_ENDPOINT = 'https://ids.api.gcprivacy.id/v4/sync/api'

/** Default minimum hours between syncs (overridable via GROWTHCODE_TTL_HOURS). */
export const GROWTHCODE_DEFAULT_TTL_HOURS = 48

/** The reserved "null" advertising id — sent when the device has no usable
 *  IDFA/GAID (ATT denied / limited ad tracking). GrowthCode still accepts it. */
export const GROWTHCODE_NULL_MAID = '00000000-0000-0000-0000-000000000000'

/** Resolved GrowthCode settings after applying local → remote → default. */
export interface ResolvedGrowthCode {
  enabled: boolean
  partnerId?: string
  endpoint: string
  syncUrl?: string
  sendMaid: boolean
  ttlHours: number
}

/** Relevant fields of the GrowthCode sync response. Extra fields are ignored. */
export interface GrowthCodeResponse {
  /** `gc_id` — the GCID to persist and replay on the next sync. */
  gcId?: string
  /** `eb` — serialized EID blob for direct injection into the bid stream. */
  eidBlob?: string
  /** `idi` — whether ID injection is enabled for this response. */
  idInject?: boolean
  /** `version` — response schema version. */
  version?: number
}

function truthy(value: unknown): boolean {
  if (typeof value === 'boolean') return value
  if (typeof value === 'number') return value !== 0
  if (typeof value === 'string') return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase())
  return false
}

function numeric(value: unknown): number | undefined {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value === 'string') {
    const n = Number(value)
    if (Number.isFinite(n)) return n
  }
  return undefined
}

function nonEmpty(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined
}

/**
 * Resolve GrowthCode settings with the SDK's standard precedence:
 * local typed `config.growthCode.*` → raw remote `GROWTHCODE_*` → default.
 *
 * `enabled` additionally honours the per-zone map (`GROWTHCODE_ENABLED_BY_ZONE`)
 * when the global remote flag is falsy, matching the video/native toggles.
 */
export function resolveGrowthCode(
  config: Pick<SellwildConfig, 'growthCode' | 'remote'>,
  zoneId?: string | number | null,
): ResolvedGrowthCode {
  const { settings, issues } = resolveGrowthCodeWithIssues(config, zoneId)
  report(issues)
  return settings
}

/**
 * resolveGrowthCode, plus growthcode.config.missing when GrowthCode is on
 * but the partner id or the sync URL is missing, so a sync can never run
 * (the native shells skip it). Pure.
 */
export function resolveGrowthCodeWithIssues(
  config: Pick<SellwildConfig, 'growthCode' | 'remote'>,
  zoneId?: string | number | null,
): { settings: ResolvedGrowthCode; issues: LogFailureInput[] } {
  const local = config.growthCode ?? {}
  const remote = config.remote ?? {}

  let enabled: boolean
  if (typeof local.enabled === 'boolean') {
    enabled = local.enabled
  } else if (truthy(remote['GROWTHCODE_ENABLED'])) {
    enabled = true
  } else if (zoneId != null) {
    const byZone = remote['GROWTHCODE_ENABLED_BY_ZONE']
    const perZone =
      byZone && typeof byZone === 'object'
        ? (byZone as Record<string, unknown>)[String(zoneId)]
        : undefined
    enabled = perZone === undefined ? false : truthy(perZone)
  } else {
    enabled = false
  }

  const sendMaid =
    typeof local.sendMaid === 'boolean'
      ? local.sendMaid
      : remote['GROWTHCODE_SEND_MAID'] === undefined
        ? true
        : truthy(remote['GROWTHCODE_SEND_MAID'])

  const settings: ResolvedGrowthCode = {
    enabled,
    partnerId: local.partnerId ?? nonEmpty(remote['GROWTHCODE_PARTNER_ID']),
    endpoint: local.endpoint ?? nonEmpty(remote['GROWTHCODE_ENDPOINT']) ?? GROWTHCODE_DEFAULT_ENDPOINT,
    syncUrl: local.syncUrl ?? nonEmpty(remote['GROWTHCODE_SYNC_URL']),
    sendMaid,
    // A GROWTHCODE_TTL_HOURS that is not a number is not reported: it reads
    // as the default, the same as leaving it unset, and the sync still runs.
    ttlHours: local.ttlHours ?? numeric(remote['GROWTHCODE_TTL_HOURS']) ?? GROWTHCODE_DEFAULT_TTL_HOURS,
  }
  const missing = [settings.partnerId ? '' : 'partner id', settings.syncUrl ? '' : 'sync URL'].filter(Boolean)
  const issues: LogFailureInput[] =
    settings.enabled && missing.length > 0
      ? [issue('growthcode.config.missing', `GrowthCode is on without a ${missing.join(' or ')}, so it never syncs`, zoneId)]
      : []
  return { settings, issues }
}

/**
 * Whether a sync should run now. Calls GrowthCode only when there is no stored
 * GCID, or when at least `ttlHours` have elapsed since the last sync — so we
 * never pay for a call inside the throttle window.
 */
export function shouldSync(
  gcid: string | null | undefined,
  lastSyncAtMs: number | null | undefined,
  ttlHours: number,
  nowMs: number,
): boolean {
  if (!gcid) return true
  if (lastSyncAtMs == null) return true
  return nowMs - lastSyncAtMs >= ttlHours * 3_600_000
}

/**
 * Parse the GrowthCode `eb` (EID blob) — a JSON string of
 * `[{ inserter, source, matcher?, uids: [{ id, atype?, stype? }] }]` — into
 * `SellwildEid[]`. The provider-only `inserter`/`matcher` fields are dropped;
 * a uid's `stype` (when present without `atype`) is preserved in `ext`.
 * Returns `[]` for null/empty/malformed input (never throws). Malformed input
 * is reported: growthcode.eid.parse (not JSON) and growthcode.eid.invalid (not
 * an array, or entries or uids dropped).
 */
export function parseEidBlob(eb: string | null | undefined): SellwildEid[] {
  const { eids, issues } = parseEidBlobWithIssues(eb)
  report(issues)
  return eids
}

/** parseEidBlob, plus what it had to drop. Pure. */
export function parseEidBlobWithIssues(eb: string | null | undefined): { eids: SellwildEid[]; issues: LogFailureInput[] } {
  if (!eb) return { eids: [], issues: [] }
  let parsed: unknown
  try {
    parsed = JSON.parse(eb)
  } catch (error) {
    // The parse error's message quotes part of the blob, an identity token
    // that is never sent (FAILURES.md 7.6): only its name goes.
    return { eids: [], issues: [issue('growthcode.eid.parse', 'eid blob is not JSON', undefined, parseErrorName(error))] }
  }
  if (!Array.isArray(parsed)) {
    return { eids: [], issues: [issue('growthcode.eid.invalid', `eid blob is ${jsonKind(parsed)}, not a list`)] }
  }

  const eids: SellwildEid[] = []
  let droppedEntries = 0
  let droppedUids = 0
  for (const entry of parsed) {
    const source = entry && typeof entry === 'object' ? nonEmpty((entry as Record<string, unknown>).source) : undefined
    const rawUids = source ? (entry as Record<string, unknown>).uids : undefined
    if (!source || !Array.isArray(rawUids)) {
      droppedEntries++
      continue
    }

    const uids: SellwildEidUid[] = []
    for (const u of rawUids) {
      const id = u && typeof u === 'object' ? nonEmpty((u as Record<string, unknown>).id) : undefined
      if (!id) {
        droppedUids++
        continue
      }
      const atype = numeric((u as Record<string, unknown>).atype)
      const stype = nonEmpty((u as Record<string, unknown>).stype)
      uids.push({
        id,
        atype: atype ?? 0,
        ...(stype ? { ext: { stype } } : {}),
      })
    }
    if (uids.length > 0) eids.push({ source, uids })
    else droppedEntries++
  }
  const issues =
    droppedEntries + droppedUids > 0
      ? [issue('growthcode.eid.invalid', `eid blob: dropped ${droppedEntries} of ${parsed.length} entries and ${droppedUids} uids without source, uids or id`)]
      : []
  return { eids, issues }
}

/**
 * Merge GrowthCode-resolved eids with the partner's explicitly-set eids.
 * Explicit consumer eids WIN on a source conflict: a source present in
 * `consumer` fully suppresses GrowthCode's entry for that same source.
 * Consumer eids come first, then GrowthCode's non-conflicting sources.
 */
export function mergeEids(consumer: SellwildEid[], growthcode: SellwildEid[]): SellwildEid[] {
  const consumerSources = new Set(consumer.map((e) => e.source))
  return [...consumer, ...growthcode.filter((e) => !consumerSources.has(e.source))]
}

/** Build the sync request URL — `pid` and `u` ride the query string. */
export function buildSyncUrl(endpoint: string, partnerId: string, syncUrl: string): string {
  const sep = endpoint.includes('?') ? '&' : '?'
  return `${endpoint}${sep}pid=${encodeURIComponent(partnerId)}&u=${encodeURIComponent(syncUrl)}`
}

/** Fields for the form-encoded sync body (all optional; omit empties). */
export interface GrowthCodeSyncBody {
  gcid?: string | null
  h?: string | null
  ref?: string | null
  maid?: string | null
  maidType?: string | null
}

/** Build the `application/x-www-form-urlencoded` sync body. */
export function buildSyncBody(fields: GrowthCodeSyncBody): string {
  const parts: string[] = []
  const add = (k: string, v?: string | null) => {
    if (v) parts.push(`${k}=${encodeURIComponent(v)}`)
  }
  add('gcid', fields.gcid)
  add('h', fields.h)
  add('ref', fields.ref)
  add('maid', fields.maid)
  add('maid_type', fields.maidType)
  return parts.join('&')
}

/**
 * Extract the fields the SDK cares about from a parsed sync response object.
 * A response that is not an object is reported (growthcode.sync.invalid).
 */
export function parseGrowthCodeResponse(json: Record<string, unknown> | null | undefined): GrowthCodeResponse {
  const { response, issues } = parseGrowthCodeResponseWithIssues(json)
  report(issues)
  return response
}

/** parseGrowthCodeResponse, plus growthcode.sync.invalid when `json` is not an object. Pure. */
export function parseGrowthCodeResponseWithIssues(json: unknown): { response: GrowthCodeResponse; issues: LogFailureInput[] } {
  const issues =
    json && typeof json === 'object' && !Array.isArray(json)
      ? []
      : [issue('growthcode.sync.invalid', `sync response is ${jsonKind(json)}, not an object`)]
  // An array still reads as an object here, as it always has (every field undefined).
  if (!json || typeof json !== 'object') return { response: {}, issues }
  const body = json as Record<string, unknown>
  return {
    response: {
      gcId: nonEmpty(body['gc_id']),
      eidBlob: nonEmpty(body['eb']),
      idInject: typeof body['idi'] === 'boolean' ? (body['idi'] as boolean) : undefined,
      version: numeric(body['version']),
    },
    issues,
  }
}

function issue(
  code: 'growthcode.config.missing' | 'growthcode.eid.parse' | 'growthcode.eid.invalid' | 'growthcode.sync.invalid',
  message: string,
  zoneId?: string | number | null,
  error?: unknown,
): LogFailureInput {
  return {
    code,
    component: 'growthcode',
    severity: 'warn',
    message,
    ...(zoneId != null ? { zoneId } : {}),
    ...(error !== undefined ? { error } : {}),
  }
}

function report(issues: readonly LogFailureInput[]): void {
  for (const i of issues) logFailure(i)
}
