// The localized (per-state) listings integration: its config object
// (LOCALIZED_LISTINGS or config.localizedListings) and the per-state cache
// response. Response default: the real Alabama sports cache.

import type { LocalizedListingsConfig } from '../../src/types'
import { fixtureVariants, invalidCases, invalidPayload, load, sampleVariants, type InvalidCase } from './base'
import type { ListingsResultPayload } from './listingsResponse'

/** The core type, except the CMS may send `frequency` as text. */
export type LocalizedListingsConfigPayload = Omit<LocalizedListingsConfig, 'frequency'> & { frequency?: number | string }

export const localizedListingsConfigVariants = fixtureVariants('localized-listings-config')

export function localizedListingsConfig(
  overrides: Partial<LocalizedListingsConfigPayload> = {},
  variant = 'full',
): LocalizedListingsConfigPayload {
  return { ...load<LocalizedListingsConfigPayload>('localized-listings-config', localizedListingsConfigVariants, variant), ...overrides }
}

export function invalidLocalizedListingsConfigs(): InvalidCase[] {
  return invalidCases('localized-listings-config')
}

/** One invalid localized-listings-config fixture by name, marker dropped. */
export function invalidLocalizedListingsConfig(name: string): Record<string, unknown> {
  return invalidPayload('localized-listings-config', name)
}

export interface LocalizedListingsResultPayload extends ListingsResultPayload {
  /** Upper-case state the cache is for. */
  state: string
}

export interface LocalizedListingsResponsePayload {
  result: LocalizedListingsResultPayload
  [key: string]: unknown
}

export const localizedListingsResponseVariants = {
  ...sampleVariants('localized-listings-response'),
  ...fixtureVariants('localized-listings-response'),
}

/** Overrides apply to `result`. */
export function localizedListingsResponse(
  overrides: Partial<LocalizedListingsResultPayload> = {},
  variant = 'sports-img-data-sm-webp-al',
): LocalizedListingsResponsePayload {
  const body = load<LocalizedListingsResponsePayload>('localized-listings-response', localizedListingsResponseVariants, variant)
  return { ...body, result: { ...body.result, ...overrides } }
}

export function invalidLocalizedListingsResponses(): InvalidCase[] {
  return invalidCases('localized-listings-response')
}
