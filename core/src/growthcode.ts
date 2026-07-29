// growthcode.ts — GrowthCode Signal Resolve (identity) core logic.
//
// GrowthCode is an identity provider. The SDK POSTs a "sync" to GrowthCode
// with (optionally) the device advertising id and a stored GCID; GrowthCode
// returns a GCID to persist and an EID blob to merge into the Prebid auction.
//
// This module is the PLATFORM-NEUTRAL reference: request/response shapes, the
// EID-blob parser, the consumer-wins merge, the sync throttle, and the
// local→remote→default settings resolution. It performs no I/O — no network,
// no storage, no device-id access. The native SDKs (iOS/Android) mirror these
// functions with their own HTTP/persistence/advertising-id adapters, and a
// future web build can call these directly.
//
// API contract (GrowthCode Signal Resolve v1.0, direct API):
//   POST {endpoint}?pid={partnerId}&u={syncUrl}
//   Content-Type: application/x-www-form-urlencoded
//   body: gcid, h, ref, h1 (HEM md5), h3 (HEM sha256), maid, maid_type
// Response JSON: gc_id, eb (serialized EID blob), idi, version, plus web-only
// directives (cookies/kv/dl/ls, bucket, gctest, persistent) the SDK ignores.

import type { SellwildEid, SellwildEidUid, SellwildConfig, GrowthCodeConfig } from './types'

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

  return {
    enabled,
    partnerId: local.partnerId ?? nonEmpty(remote['GROWTHCODE_PARTNER_ID']),
    endpoint: local.endpoint ?? nonEmpty(remote['GROWTHCODE_ENDPOINT']) ?? GROWTHCODE_DEFAULT_ENDPOINT,
    syncUrl: local.syncUrl ?? nonEmpty(remote['GROWTHCODE_SYNC_URL']),
    sendMaid,
    ttlHours: local.ttlHours ?? numeric(remote['GROWTHCODE_TTL_HOURS']) ?? GROWTHCODE_DEFAULT_TTL_HOURS,
  }
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
 * Returns `[]` for null/empty/malformed input (never throws).
 */
export function parseEidBlob(eb: string | null | undefined): SellwildEid[] {
  if (!eb) return []
  let parsed: unknown
  try {
    parsed = JSON.parse(eb)
  } catch {
    return []
  }
  if (!Array.isArray(parsed)) return []

  const eids: SellwildEid[] = []
  for (const entry of parsed) {
    if (!entry || typeof entry !== 'object') continue
    const source = nonEmpty((entry as Record<string, unknown>).source)
    const rawUids = (entry as Record<string, unknown>).uids
    if (!source || !Array.isArray(rawUids)) continue

    const uids: SellwildEidUid[] = []
    for (const u of rawUids) {
      if (!u || typeof u !== 'object') continue
      const id = nonEmpty((u as Record<string, unknown>).id)
      if (!id) continue
      const atype = numeric((u as Record<string, unknown>).atype)
      const stype = nonEmpty((u as Record<string, unknown>).stype)
      uids.push({
        id,
        atype: atype ?? 0,
        ...(stype ? { ext: { stype } } : {}),
      })
    }
    if (uids.length > 0) eids.push({ source, uids })
  }
  return eids
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

/** Extract the fields the SDK cares about from a parsed sync response object. */
export function parseGrowthCodeResponse(json: Record<string, unknown> | null | undefined): GrowthCodeResponse {
  if (!json || typeof json !== 'object') return {}
  return {
    gcId: nonEmpty(json['gc_id']),
    eidBlob: nonEmpty(json['eb']),
    idInject: typeof json['idi'] === 'boolean' ? (json['idi'] as boolean) : undefined,
    version: numeric(json['version']),
  }
}
