// GrowthCode sync response (POST ids.api.gcprivacy.id/v4/sync/api) and the
// parsed EID blob inside its `eb` text. Never sampled live (POST), so the
// bases are the contract fixtures.

import { fixtureVariants, invalidCases, load, type InvalidCase } from './base'

export interface GrowthCodeSyncResponsePayload {
  gc_id?: string | null
  /** The EID blob as JSON text; see eidBlob(). */
  eb?: string | null
  idi?: boolean
  version?: number
  [key: string]: unknown
}

export const growthCodeSyncResponseVariants = fixtureVariants('growthcode-sync-response')

export function growthCodeSyncResponse(
  overrides: Partial<GrowthCodeSyncResponsePayload> = {},
  variant = 'full',
): GrowthCodeSyncResponsePayload {
  return { ...load<GrowthCodeSyncResponsePayload>('growthcode-sync-response', growthCodeSyncResponseVariants, variant), ...overrides }
}

export function invalidGrowthCodeSyncResponses(): InvalidCase[] {
  return invalidCases('growthcode-sync-response')
}

export interface EidUidPayload {
  id: string
  atype?: number | string
  stype?: string
  [key: string]: unknown
}

export interface EidEntryPayload {
  source: string
  uids: EidUidPayload[]
  inserter?: string
  matcher?: string
  [key: string]: unknown
}

export const eidBlobVariants = fixtureVariants('eid-blob')

/** A parsed EID blob. `entries` replaces the variant's entries. */
export function eidBlob(entries?: EidEntryPayload[], variant = 'full'): EidEntryPayload[] {
  return entries ?? load<EidEntryPayload[]>('eid-blob', eidBlobVariants, variant)
}

/** One blob entry: the first entry of the `full` fixture with overrides. */
export function eidEntry(overrides: Partial<EidEntryPayload> = {}): EidEntryPayload {
  return { ...eidBlob()[0], ...overrides }
}

export function invalidEidBlobs(): InvalidCase[] {
  return invalidCases('eid-blob')
}
