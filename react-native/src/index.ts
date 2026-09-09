export { SellwildWidget } from './SellwildWidget'
export type { SellwildWidgetProps } from './SellwildWidget'

export { SellwildBanner } from './SellwildBanner'
export type { SellwildBannerProps } from './SellwildBanner'

export { SellwildFeed } from './SellwildFeed'
export type { SellwildFeedProps } from './SellwildFeed'

export { SellwildListingCard } from './SellwildListingCard'
export type { SellwildListingCardProps } from './SellwildListingCard'

export { useSellwildListings } from './useSellwildListings'
export type { UseSellwildListingsResult } from './useSellwildListings'

// Imperative native setters (runtime, session-scoped).
export { setGeo, setExternalUserIds } from './commands'

// Re-export core types for convenience
export type {
  SellwildConfig,
  PartialSellwildConfig,
  SellwildListing,
  SellwildListingsResponse,
  SellwildPhoto,
  SellwildUser,
  PrebidServerConfig,
  SellwildGeo,
  SellwildEid,
  SellwildEidUid,
  AdSize,
  AdPlacement,
  AdPlacementType,
} from '@sellwild/sdk-core'

export {
  configure,
  buildConfig,
  buildConfigWithRemote,
  currencyToSymbol,
  fetchRemoteConfig,
  clearRemoteConfigCache,
} from '@sellwild/sdk-core'

export type { ConfigureOptions } from '@sellwild/sdk-core'

// Stamp every analytics event with the host platform. Runs once on module load
// so any code path that reaches the shared core `eventQueue` is attributed to
// react-native (merged into `attributes.platform` alongside `sdkVersion`).
import { eventQueue } from '@sellwild/sdk-core'
eventQueue.setPlatform('react-native')
