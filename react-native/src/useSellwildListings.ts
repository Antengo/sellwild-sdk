import { useState, useEffect, useCallback } from 'react'
import type { SellwildConfig, SellwildListing, SellwildListingsResponse } from '@sellwild/sdk-core'
import { fetchListings, clearListingCache } from '@sellwild/sdk-core'

export interface UseSellwildListingsResult {
  listings: SellwildListing[]
  config: Record<string, unknown>
  loading: boolean
  error: Error | null
  refresh: () => void
}

export function useSellwildListings(sdkConfig: SellwildConfig): UseSellwildListingsResult {
  const [listings, setListings] = useState<SellwildListing[]>([])
  const [config, setConfig] = useState<Record<string, unknown>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

  const refresh = useCallback(() => setRefreshKey(k => k + 1), [])

  useEffect(() => {
    let cancelled = false
    const controller = new AbortController()

    setLoading(true)
    setError(null)

    // Clear cache so refresh actually re-fetches from the network
    if (refreshKey > 0) clearListingCache()

    fetchListings(sdkConfig, { signal: controller.signal })
      .then((result: SellwildListingsResponse) => {
        if (cancelled) return
        setListings(result.listings)
        setConfig(result.config)
      })
      // eslint-disable-next-line sellwild/catch-reports-failure -- FAILURES.md 9.2: log once; core's fetchListings already logged it
      .catch((err: Error) => {
        // Not logged here: core's fetchListings already logged this failure
        // (listings.fetch.*), and a failure is logged once, at the lowest layer
        // (contracts/FAILURES.md 9). This only hands it to the host.
        if (cancelled) return
        // Our own abort (unmount or a new fetch): a caller abort, not a failure.
        if (err.name === 'AbortError') return
        setError(err)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => {
      cancelled = true
      controller.abort()
    }
  }, [sdkConfig.listingsUrl, refreshKey])

  return { listings, config, loading, error, refresh }
}
