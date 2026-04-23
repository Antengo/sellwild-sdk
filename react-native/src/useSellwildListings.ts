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
      .catch((err: Error) => {
        if (cancelled) return
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
