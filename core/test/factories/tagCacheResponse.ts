// The tag-cache listings response (fetchTagCacheListings): a bare JSON array
// of listing items. There is no schema of its own; each item must pass the
// listing schema. Default: three listing variants.

import { listing, type ListingPayload } from './listing'

export function tagCacheResponse(listings?: ListingPayload[]): ListingPayload[] {
  return listings ?? [listing(), listing({}, 'bargainhunter-item'), listing({}, 'numeric-id')]
}
