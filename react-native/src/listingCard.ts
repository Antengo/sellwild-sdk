import type { SellwildListing } from '@sellwild/sdk-core'
import { currencyToSymbol } from '@sellwild/sdk-core'
import { jsonKind } from './jsonKind'

// Pure view model of <SellwildListingCard>: what the card shows for a
// listing, and what in the listing it could not show.

export interface ListingCardView {
  /** The first photo's URL, or null for the placeholder. */
  photoUrl: string | null
  /** The formatted price, or null when there is none to show. */
  price: string | null
  /** The formatted strike price, or null. */
  strikePrice: string | null
  /** Whether the badge shows (a price other than '0'). */
  showPrice: boolean
  /** Whether the badge also shows the strike price (set and not the price). */
  showStrike: boolean
  currencySymbol: string
  /** The title, cut to 60 characters plus '...'. */
  title: string
  /**
   * Fields that have a value the card cannot show (listings.item.invalid):
   * the field and the JSON kind, never the value, which may be listing text.
   */
  issues: string[]
}

type PriceField = 'price' | 'strikePrice'

// A price as the card shows it, or null. A number, or text that Number()
// reads (the caches send numeric text), is shown; empty, null and absent mean
// there is none. Text that Number() cannot read ('Call us') is hidden, as
// before, and is not an issue: listing.schema.json allows any text for a
// price (numOrNumericString is number | string), so it is not a failure. A
// value the contract does not allow is an issue: before, a boolean `true`
// showed as "$1" and a one-element array as its element.
function formatPrice(
  listing: SellwildListing,
  field: PriceField,
  locale: string | undefined,
  issues: string[],
): string | null {
  const value: unknown = listing[field]
  if (value == null || value === '') return null
  if (typeof value !== 'number' && typeof value !== 'string') {
    issues.push(`${field} is ${jsonKind(value)}`)
    return null
  }
  const n = Number(value)
  if (isNaN(n)) {
    if (typeof value === 'number') issues.push(`${field} is NaN`)
    return null
  }
  // 0 and '0' mean no price, as before (the badge hides '0').
  if (n === 0 && typeof value === 'number') return null
  return n.toLocaleString(locale, { maximumFractionDigits: 0 })
}

// The first photo's URL. No photos is a listing without one; a first photo
// without a URL string is an issue.
function photoUrlOf(listing: SellwildListing, issues: string[]): string | null {
  const photos: unknown = listing.photos
  if (photos == null) return null
  if (!Array.isArray(photos)) {
    issues.push(`photos is ${jsonKind(photos)}`)
    return null
  }
  if (photos.length === 0) return null
  const url: unknown = (photos[0] as { url?: unknown } | null)?.url
  if (typeof url === 'string' && url !== '') return url
  issues.push(`photos[0] url is ${url === '' ? 'empty' : jsonKind(url)}`)
  return null
}

/** What the card shows for `listing`. `locale` is for tests; the card passes undefined (the device locale). */
export function listingCardView(listing: SellwildListing, locale?: string): ListingCardView {
  const issues: string[] = []
  const photoUrl = photoUrlOf(listing, issues)
  const price = formatPrice(listing, 'price', locale, issues)
  const strikePrice = formatPrice(listing, 'strikePrice', locale, issues)
  const title = listing.title?.length > 60
    ? listing.title.slice(0, 60) + '...'
    : listing.title
  const showPrice = price !== null && price !== '0'
  return {
    photoUrl,
    price,
    strikePrice,
    showPrice,
    showStrike: showPrice && strikePrice !== null && strikePrice !== price,
    currencySymbol: currencyToSymbol(listing.currency),
    title,
    issues,
  }
}
