// One listing as the caches send it (not the stricter SellwildListing type).
// Default: the first item of the real listings-img-data-sm cache.

import { contract } from '../support/contracts'
import { fixtureVariants, invalidCases, load, type InvalidCase } from './base'

export interface ListingPhotoPayload {
  url: string
  [key: string]: unknown
}

export interface ListingPayload {
  id: string | number
  title: string
  photos: ListingPhotoPayload[]
  price?: string | number
  status?: string
  shippable?: boolean | string
  remote_url?: string | null
  categoryGroupId?: string
  dataSourceId?: string
  user?: { id?: string | number; firstName?: string; lastName?: string; trustLevel?: string; [key: string]: unknown }
  [key: string]: unknown
}

export const listingVariants = {
  'cache-sample': () => contract<{ result: { rs: unknown[] } }>('samples/listings-response/listings-img-data-sm.json').result.rs[0],
  ...fixtureVariants('listing'),
}

export function listing(overrides: Partial<ListingPayload> = {}, variant = 'cache-sample'): ListingPayload {
  return { ...load<ListingPayload>('listing', listingVariants, variant), ...overrides }
}

export function invalidListings(): InvalidCase[] {
  return invalidCases('listing')
}
