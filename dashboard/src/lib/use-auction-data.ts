'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import type {
  Overview,
  BidderSummary,
  LatencyBucket,
  VolumeBucket,
  CpmSnapshot,
  AuctionQueryFilters,
} from './athena-types';

async function fetchType<T>(type: string, filters: AuctionQueryFilters): Promise<T> {
  const params = new URLSearchParams({ type });
  if (filters.hours) params.set('hours', String(filters.hours));
  const res = await fetch(`/api/auctions?${params}`);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`${type}: ${body}`);
  }
  return res.json();
}

export function useAuctionDashboard(initialFilters: AuctionQueryFilters = { hours: 24 }) {
  const [filters, setFilters] = useState<AuctionQueryFilters>(initialFilters);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const [overview, setOverview] = useState<Overview | null>(null);
  const [bidderSummary, setBidderSummary] = useState<BidderSummary[]>([]);
  const [latencyTrend, setLatencyTrend] = useState<LatencyBucket[]>([]);
  const [volumeTrend, setVolumeTrend] = useState<VolumeBucket[]>([]);
  const [cpmSnapshot, setCpmSnapshot] = useState<CpmSnapshot[]>([]);

  const fetchAll = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [o, b, l, v, c] = await Promise.all([
        fetchType<Overview>('overview', filters),
        fetchType<BidderSummary[]>('bidder_summary', filters),
        fetchType<LatencyBucket[]>('latency_trend', filters),
        fetchType<VolumeBucket[]>('volume_trend', filters),
        fetchType<CpmSnapshot[]>('cpm_snapshot', filters),
      ]);
      setOverview(o);
      setBidderSummary(b);
      setLatencyTrend(l);
      setVolumeTrend(v);
      setCpmSnapshot(c);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load data');
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  useEffect(() => {
    if (autoRefresh) {
      intervalRef.current = setInterval(fetchAll, 30000);
    }
    return () => { if (intervalRef.current) clearInterval(intervalRef.current); };
  }, [autoRefresh, fetchAll]);

  return {
    filters, setFilters,
    loading, error,
    autoRefresh, setAutoRefresh,
    overview, bidderSummary, latencyTrend, volumeTrend, cpmSnapshot,
    refresh: fetchAll,
  };
}
