/** Types for Prebid Server metrics from Athena */

export interface Overview {
  period_hours: number;
  total_auctions_lifetime: number;
  auctions_in_period: number;
  latency: {
    mean_ms: number;
    median_ms: number;
    p95_ms: number;
    p99_ms: number;
    min_ms: number;
    max_ms: number;
  };
  impressions: {
    banner: number;
    requested: number;
    video: number;
  };
  requests: {
    web: number;
    app: number;
  };
  active_bidders: number;
  requests_per_sec: number;
}

export interface BidderSummary {
  bidder: string;
  gotbids: number;
  nobid: number;
  timeout: number;
  errors: number;
  total: number;
  fill_rate: number;
  error_rate: number;
  cpm: {
    avg: number;
    median: number;
    min: number;
    max: number;
    p95: number;
    total_bids: number;
  } | null;
}

export interface LatencyBucket {
  bucket: string;
  mean_ms: number;
  median_ms: number;
  p95_ms: number;
  p99_ms: number;
  max_ms: number;
  requests: number;
}

export interface VolumeBucket {
  bucket: string;
  [key: string]: string | number;
}

export interface CpmSnapshot {
  bidder: string;
  total_bids: number;
  avg_cpm: number;
  median_cpm: number;
  min_cpm: number;
  max_cpm: number;
  p75_cpm: number;
  p95_cpm: number;
  p99_cpm: number;
  stddev_cpm: number;
}

export interface AuctionQueryFilters {
  hours?: number;
}
