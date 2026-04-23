/**
 * Netlify Function: /.netlify/functions/auctions
 *
 * Auction analytics API — queries Prebid Server metrics from Athena.
 *
 * Data model:
 *   - Counter table uses flushing counters (ResettingCounter). Each row's
 *     `count` is the number of events in that ~30s interval, NOT cumulative.
 *     Use SUM(count) to aggregate over a time window.
 *   - Timer/Histogram `count` IS cumulative (total since JVM start).
 *     Percentiles (mean, p95, p99) are reservoir snapshots (point-in-time).
 *   - Histogram prices are in millidollars (CPM × 1000). Divide by 1000
 *     to get CPM in dollars.
 *   - Timer `median` column is NULL — use mean or p75 as proxy.
 */

import type { Handler } from '@netlify/functions'
import { queryAthena } from './lib/athena-client'

function param(url: URL, key: string): string | undefined {
  return url.searchParams.get(key) || undefined
}

function hoursParam(url: URL): number {
  return parseInt(param(url, 'hours') || '24', 10) || 24
}

function bucketForHours(hours: number): string {
  if (hours <= 6) return 'minute'
  if (hours <= 48) return 'hour'
  return 'day'
}

function json(body: unknown, status = 200) {
  return {
    statusCode: status,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  }
}

export const handler: Handler = async (event) => {
  const url = new URL(event.rawUrl)
  const type = param(url, 'type') || 'overview'
  const hours = hoursParam(url)

  try {
    switch (type) {
      // ─────────────────────────────────────────────────────────────────
      // OVERVIEW — KPI summary
      // ─────────────────────────────────────────────────────────────────
      case 'overview': {
        const [timer, counters, bidders] = await Promise.all([
          // Latest latency snapshot (timer count is cumulative = lifetime total)
          queryAthena<Record<string, string>>(`
            SELECT count, mean, p75, p95, p99, min, max, mean_rate
            FROM timer WHERE name = 'request_time'
            ORDER BY timestamp DESC LIMIT 1
          `),
          // SUM flushing counters over the time window
          queryAthena<Record<string, string>>(`
            SELECT name, SUM(count) AS total
            FROM counter
            WHERE name IN ('requests.ok.openrtb2-web','requests.ok.openrtb2-app',
                           'imps_banner','imps_requested','imps_video','app_requests')
              AND timestamp >= date_add('hour', -${hours}, now())
            GROUP BY name
          `),
          // Count active bidders (those with price data in the window)
          queryAthena<Record<string, string>>(`
            SELECT count(DISTINCT regexp_extract(name, 'adapter\\.([^.]+)\\.prices', 1)) AS cnt
            FROM histogram WHERE name LIKE 'adapter.%.prices'
              AND timestamp >= date_add('hour', -${hours}, now())
          `),
        ])

        const t = timer[0] || {}
        const cMap: Record<string, number> = {}
        counters.forEach((r) => {
          cMap[r.name] = parseInt(r.total) || 0
        })

        return json({
          period_hours: hours,
          total_auctions_lifetime: parseInt(t.count || '0'),
          auctions_in_period: (cMap['requests.ok.openrtb2-web'] || 0) + (cMap['requests.ok.openrtb2-app'] || 0),
          latency: {
            mean_ms: parseFloat(parseFloat(t.mean || '0').toFixed(1)),
            median_ms: parseFloat(parseFloat(t.p75 || t.mean || '0').toFixed(1)),
            p95_ms: parseFloat(parseFloat(t.p95 || '0').toFixed(1)),
            p99_ms: parseFloat(parseFloat(t.p99 || '0').toFixed(1)),
            min_ms: parseFloat(parseFloat(t.min || '0').toFixed(1)),
            max_ms: parseFloat(parseFloat(t.max || '0').toFixed(1)),
          },
          impressions: {
            banner: cMap['imps_banner'] || 0,
            requested: cMap['imps_requested'] || 0,
            video: cMap['imps_video'] || 0,
          },
          requests: {
            web: cMap['requests.ok.openrtb2-web'] || 0,
            app: cMap['requests.ok.openrtb2-app'] || 0,
          },
          active_bidders: parseInt(bidders[0]?.cnt || '0'),
          requests_per_sec: parseFloat(parseFloat(t.mean_rate || '0').toFixed(2)),
        })
      }

      // ─────────────────────────────────────────────────────────────────
      // BIDDER SUMMARY — per-SSP fill rate, errors, CPM
      // ─────────────────────────────────────────────────────────────────
      case 'bidder_summary': {
        const [requestStats, priceStats] = await Promise.all([
          // SUM flushing counters per bidder per metric
          queryAthena<Record<string, string>>(`
            SELECT
              regexp_extract(name, 'adapter\\.([^.]+)\\.requests\\.(.+)', 1) AS bidder,
              regexp_extract(name, 'adapter\\.([^.]+)\\.requests\\.(.+)', 2) AS metric,
              SUM(count) AS total
            FROM counter
            WHERE name LIKE 'adapter.%.requests.%'
              AND NOT name LIKE '%.type.%'
              AND timestamp >= date_add('hour', -${hours}, now())
            GROUP BY 1, 2
            HAVING SUM(count) > 0 OR 1=1
          `),
          // Latest CPM per bidder (prices in millidollars — divide by 1000)
          queryAthena<Record<string, string>>(`
            SELECT
              regexp_extract(name, 'adapter\\.([^.]+)\\.prices', 1) AS bidder,
              count AS total_bids,
              round(mean / 1000.0, 2) AS avg_cpm,
              round(COALESCE(median, mean) / 1000.0, 2) AS median_cpm,
              round(min / 1000.0, 2) AS min_cpm,
              round(max / 1000.0, 2) AS max_cpm,
              round(p95 / 1000.0, 2) AS p95_cpm
            FROM histogram
            WHERE name LIKE 'adapter.%.prices'
            ORDER BY timestamp DESC
            LIMIT 10
          `),
        ])

        // Pivot request stats: bidder -> { gotbids, nobid, timeout, ... }
        const bidderMap: Record<string, Record<string, number>> = {}
        requestStats.forEach((r) => {
          if (!bidderMap[r.bidder]) bidderMap[r.bidder] = {}
          bidderMap[r.bidder]![r.metric] = parseInt(r.total) || 0
        })

        // Latest price per bidder (dedup)
        const prices: Record<string, Record<string, string>> = {}
        priceStats.forEach((r) => {
          if (!prices[r.bidder]) prices[r.bidder] = r
        })

        return json(
          Object.entries(bidderMap)
            .sort(([a], [b]) => a.localeCompare(b))
            .map(([bidder, metrics]) => {
              const gotbids = metrics['gotbids'] || 0
              const nobid = metrics['nobid'] || 0
              const timeout = metrics['timeout'] || 0
              const badinput = metrics['badinput'] || 0
              const badresponse = metrics['badserverresponse'] || 0
              const unknown = metrics['unknown_error'] || 0
              const total = gotbids + nobid + timeout + badinput + badresponse + unknown
              const errs = timeout + badinput + badresponse + unknown
              const p = prices[bidder]

              return {
                bidder,
                gotbids,
                nobid,
                timeout,
                errors: errs,
                total,
                fill_rate: total > 0 ? parseFloat((100 * gotbids / total).toFixed(1)) : 0,
                error_rate: total > 0 ? parseFloat((100 * errs / total).toFixed(1)) : 0,
                cpm: p
                  ? {
                      avg: parseFloat(p.avg_cpm),
                      median: parseFloat(p.median_cpm),
                      min: parseFloat(p.min_cpm),
                      max: parseFloat(p.max_cpm),
                      p95: parseFloat(p.p95_cpm),
                      total_bids: parseInt(p.total_bids),
                    }
                  : null,
              }
            })
        )
      }

      // ─────────────────────────────────────────────────────────────────
      // LATENCY TREND — time-bucketed latency percentiles
      // Timer count is cumulative, so max-min gives requests per bucket.
      // Percentiles are reservoir snapshots — average them for the bucket.
      // ─────────────────────────────────────────────────────────────────
      case 'latency_trend': {
        const bucket = bucketForHours(hours)
        const rows = await queryAthena<Record<string, string>>(`
          SELECT
            date_trunc('${bucket}', timestamp) AS bucket,
            round(avg(mean), 1) AS mean_ms,
            round(avg(COALESCE(median, mean)), 1) AS median_ms,
            round(max(p95), 1) AS p95_ms,
            round(max(p99), 1) AS p99_ms,
            round(max(max), 1) AS max_ms,
            max(count) - min(count) AS requests_in_bucket
          FROM timer
          WHERE name = 'request_time'
            AND timestamp >= date_add('hour', -${hours}, now())
          GROUP BY date_trunc('${bucket}', timestamp)
          ORDER BY bucket
        `)
        return json(
          rows.map((r) => ({
            bucket: r.bucket,
            mean_ms: parseFloat(r.mean_ms),
            median_ms: parseFloat(r.median_ms),
            p95_ms: parseFloat(r.p95_ms),
            p99_ms: parseFloat(r.p99_ms),
            max_ms: parseFloat(r.max_ms),
            requests: parseInt(r.requests_in_bucket) || 0,
          }))
        )
      }

      // ─────────────────────────────────────────────────────────────────
      // VOLUME TREND — time-bucketed request & impression counts
      // Counter table is flushing — SUM(count) for each bucket.
      // ─────────────────────────────────────────────────────────────────
      case 'volume_trend': {
        const bucket = bucketForHours(hours)
        const rows = await queryAthena<Record<string, string>>(`
          SELECT
            date_trunc('${bucket}', timestamp) AS bucket,
            name,
            SUM(count) AS total
          FROM counter
          WHERE name IN ('requests.ok.openrtb2-web','requests.ok.openrtb2-app',
                         'imps_banner','imps_requested')
            AND timestamp >= date_add('hour', -${hours}, now())
          GROUP BY date_trunc('${bucket}', timestamp), name
          ORDER BY bucket
        `)

        const buckets = new Map<string, Record<string, number>>()
        rows.forEach((r) => {
          if (!buckets.has(r.bucket)) buckets.set(r.bucket, {})
          const entry = buckets.get(r.bucket)!
          const key = r.name.replace('requests.ok.', '').replace('imps_', 'imps_')
          entry[key] = parseInt(r.total) || 0
        })

        return json(
          [...buckets.entries()].map(([bucket, metrics]) => ({
            bucket,
            ...metrics,
          }))
        )
      }

      // ─────────────────────────────────────────────────────────────────
      // CPM SNAPSHOT — current price distribution per bidder
      // Prices in millidollars — divide by 1000 for CPM in dollars.
      // ─────────────────────────────────────────────────────────────────
      case 'cpm_snapshot': {
        const rows = await queryAthena<Record<string, string>>(`
          WITH latest AS (
            SELECT max(timestamp) AS ts
            FROM histogram WHERE name LIKE 'adapter.%.prices'
          )
          SELECT
            regexp_extract(name, 'adapter\\.([^.]+)\\.prices', 1) AS bidder,
            count AS total_bids,
            round(mean / 1000.0, 2) AS avg_cpm,
            round(COALESCE(median, mean) / 1000.0, 2) AS median_cpm,
            round(min / 1000.0, 2) AS min_cpm,
            round(max / 1000.0, 2) AS max_cpm,
            round(p75 / 1000.0, 2) AS p75_cpm,
            round(p95 / 1000.0, 2) AS p95_cpm,
            round(p99 / 1000.0, 2) AS p99_cpm,
            round(stddev / 1000.0, 2) AS stddev_cpm
          FROM histogram, latest
          WHERE name LIKE 'adapter.%.prices'
            AND timestamp = latest.ts
          ORDER BY mean DESC
        `)
        return json(
          rows.map((r) => ({
            bidder: r.bidder,
            total_bids: parseInt(r.total_bids),
            avg_cpm: parseFloat(r.avg_cpm),
            median_cpm: parseFloat(r.median_cpm),
            min_cpm: parseFloat(r.min_cpm),
            max_cpm: parseFloat(r.max_cpm),
            p75_cpm: parseFloat(r.p75_cpm),
            p95_cpm: parseFloat(r.p95_cpm),
            p99_cpm: parseFloat(r.p99_cpm),
            stddev_cpm: parseFloat(r.stddev_cpm),
          }))
        )
      }

      // ─────────────────────────────────────────────────────────────────
      // BIDDER DETAIL — deep-dive on a single bidder
      // ─────────────────────────────────────────────────────────────────
      case 'bidder_detail': {
        const bidder = param(url, 'bidder')
        if (!bidder) {
          return json({ error: 'bidder param required' }, 400)
        }
        const safeBidder = bidder.replace(/'/g, "''")
        const bucket = bucketForHours(hours)

        const [counts, priceTrend] = await Promise.all([
          // SUM flushing counters per bucket for this bidder
          queryAthena<Record<string, string>>(`
            SELECT
              date_trunc('${bucket}', timestamp) AS bucket,
              regexp_extract(name, 'adapter\\.${safeBidder}\\.requests\\.(.+)', 1) AS metric,
              SUM(count) AS total
            FROM counter
            WHERE name LIKE 'adapter.${safeBidder}.requests.%'
              AND NOT name LIKE '%.type.%'
              AND timestamp >= date_add('hour', -${hours}, now())
            GROUP BY 1, 2
            ORDER BY bucket
          `),
          // Price trend (histogram count is cumulative — use max-min for delta)
          // Prices in millidollars — divide by 1000
          queryAthena<Record<string, string>>(`
            SELECT
              date_trunc('${bucket}', timestamp) AS bucket,
              round(avg(mean) / 1000.0, 2) AS avg_cpm,
              round(max(max) / 1000.0, 2) AS max_cpm,
              max(count) - min(count) AS bids_delta
            FROM histogram
            WHERE name = 'adapter.${safeBidder}.prices'
              AND timestamp >= date_add('hour', -${hours}, now())
            GROUP BY 1
            ORDER BY bucket
          `),
        ])

        const bucketMap = new Map<string, Record<string, number>>()
        counts.forEach((r) => {
          if (!bucketMap.has(r.bucket)) bucketMap.set(r.bucket, {})
          bucketMap.get(r.bucket)![r.metric] = parseInt(r.total) || 0
        })

        return json({
          bidder,
          period_hours: hours,
          request_trend: [...bucketMap.entries()].map(([b, metrics]) => ({
            bucket: b,
            ...metrics,
          })),
          price_trend: priceTrend.map((r) => ({
            bucket: r.bucket,
            avg_cpm: parseFloat(r.avg_cpm),
            max_cpm: parseFloat(r.max_cpm),
            bids: parseInt(r.bids_delta) || 0,
          })),
        })
      }

      default:
        return json({ error: `Unknown type: ${type}` }, 400)
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error'
    console.error('[Athena] Query error:', message)
    return json({ error: message }, 500)
  }
}
