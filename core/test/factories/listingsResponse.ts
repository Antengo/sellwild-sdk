// A listings cache response (GET cache.sellwild.com/listings-*), listings in
// result.rs. Default: the real listings-img-data-sm cache.

import { fixtureVariants, invalidCases, load, sampleVariants, type InvalidCase } from './base'
import type { ListingPayload } from './listing'

export interface ListingsResultPayload {
  rs: ListingPayload[]
  config?: Record<string, unknown>
  widgetCacheVersionId?: string
  [key: string]: unknown
}

export interface ListingsResponsePayload {
  result: ListingsResultPayload
  jsonrpc?: '2.0'
  id?: number | string
  [key: string]: unknown
}

export const listingsResponseVariants = {
  ...sampleVariants('listings-response'),
  ...fixtureVariants('listings-response'),
}

/** Overrides apply to `result`, e.g. `listingsResponse({ rs: [listing()] })`. */
export function listingsResponse(overrides: Partial<ListingsResultPayload> = {}, variant = 'listings-img-data-sm'): ListingsResponsePayload {
  const body = load<ListingsResponsePayload>('listings-response', listingsResponseVariants, variant)
  return { ...body, result: { ...body.result, ...overrides } }
}

export function invalidListingsResponses(): InvalidCase[] {
  return invalidCases('listings-response')
}
