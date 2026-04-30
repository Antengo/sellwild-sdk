/**
 * Auction analytics API — queries Prebid Server metrics from Athena.
 *
 * Query design principles:
 *   - Aggregation, not raw rows. Every query uses GROUP BY or latest-snapshot.
 *   - No arbitrary LIMITs. Result set size is bounded by the number of bidders
 *     (~8) or time buckets (hours/days), not row caps.
 *   - Delta-based rates. Counters are cumulative, so we compute deltas between
 *     first and last snapshot in the window to get actual counts for the period.
 *
 * Types:
 *   overview        — single-row KPIs: total requests, latency, impressions, bidders
 *   bidder_summary  — per-bidder: fill rate, error rate, bid count, CPM (one row per bidder)
 *   latency_trend   — hourly/daily latency percentiles for charting
 *   volume_trend    — hourly/daily request + impression volume
 *   cpm_snapshot    — current CPM distribution per bidder (from histogram)
 *   bidder_detail   — deep-dive on a single bidder: all available metrics
 */

import { NextRequest, NextResponse } from 'next/server';
import { queryAthena } from '@/lib/athena-client';

function param(url: URL, key: string): string | undefined {
  return url.searchParams.get(key) || undefined;
}

function hoursParam(url: URL): number {
  return parseInt(param(url, 'hours') || '24', 10) || 24;
}

/** Time bucket size based on window — keeps result sets small */
function bucketForHours(hours: number): string {
  if (hours <= 6) return 'minute';
  if (hours <= 48) return 'hour';
  return 'day';
}

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const type = param(url, 'type') || 'overview';
  const hours = hoursParam(url);

  try {
    switch (type) {
      // ─────────────────────────────────────────────────────────────────
      // OVERVIEW — single-row summary of current state
      // Answers: "How is our Prebid Server doing right now?"
      // ─────────────────────────────────────────────────────────────────
      case 'overview': {
        const [timer, counters, bidders] = await Promise.all([
          // Latest latency snapshot
          queryAthena<Record<string, string>>(`
            SELECT count, mean, median, p75, p95, p99, min, max, mean_rate
            FROM timer WHERE name = 'request_time'
            ORDER BY timestamp DESC LIMIT 1
          `),
          // Latest counter snapshot — delta between newest and oldest in window
          queryAthena<Record<string, string>>(`
            WITH bounds AS (
              SELECT
                min(timestamp) AS t_start,
                max(timestamp) AS t_end
              FROM counter
              WHERE name = 'requests.ok.openrtb2-web'
                AND timestamp >= date_add('hour', -${hours}, now())
            ),
            first_snap AS (
              SELECT name, count AS c_start
              FROM counter, bounds
              WHERE timestamp = bounds.t_start
                AND name IN ('requests.ok.openrtb2-web','requests.ok.openrtb2-app',
                             'imps_banner','imps_requested','imps_video','app_requests')
            ),
            last_snap AS (
              SELECT name, count AS c_end
              FROM counter, bounds
              WHERE timestamp = bounds.t_end
                AND name IN ('requests.ok.openrtb2-web','requests.ok.openrtb2-app',
                             'imps_banner','imps_requested','imps_video','app_requests')
            )
            SELECT
              last_snap.name,
              (last_snap.c_end - coalesce(first_snap.c_start, 0)) AS delta,
              last_snap.c_end AS total
            FROM last_snap
            LEFT JOIN first_snap ON last_snap.name = first_snap.name
          `),
          // Count active bidders (those with price data)
          queryAthena<Record<string, string>>(`
            SELECT count(DISTINCT regexp_extract(name, 'adapter\\.([^.]+)\\.prices', 1)) AS cnt
            FROM histogram WHERE name LIKE 'adapter.%.prices'
              AND timestamp >= date_add('hour', -${hours}, now())
          `),
        ]);

        const t = timer[0] || {};
        const cMap: Record<string, { delta: number; total: number }> = {};
        counters.forEach((r) => {
          cMap[r.name] = { delta: parseInt(r.delta) || 0, total: parseInt(r.total) || 0 };
        });

        return NextResponse.json({
          period_hours: hours,
          total_auctions_lifetime: parseInt(t.count || '0'),
          auctions_in_period: cMap['requests.ok.openrtb2-web']?.delta + (cMap['requests.ok.openrtb2-app']?.delta || 0),
          latency: {
            mean_ms: parseFloat(parseFloat(t.mean || '0').toFixed(1)),
            median_ms: parseFloat(parseFloat(t.median || '0').toFixed(1)),
            p95_ms: parseFloat(parseFloat(t.p95 || '0').toFixed(1)),
            p99_ms: parseFloat(parseFloat(t.p99 || '0').toFixed(1)),
            min_ms: parseFloat(parseFloat(t.min || '0').toFixed(1)),
            max_ms: parseFloat(parseFloat(t.max || '0').toFixed(1)),
          },
          impressions: {
            banner: cMap['imps_banner']?.delta || 0,
            requested: cMap['imps_requested']?.delta || 0,
            video: cMap['imps_video']?.delta || 0,
          },
          requests: {
            web: cMap['requests.ok.openrtb2-web']?.delta || 0,
            app: cMap['requests.ok.openrtb2-app']?.delta || 0,
          },
          active_bidders: parseInt(bidders[0]?.cnt || '0'),
          requests_per_sec: parseFloat(parseFloat(t.mean_rate || '0').toFixed(2)),
        });
      }

      // ─────────────────────────────────────────────────────────────────
      // BIDDER SUMMARY — one row per bidder with fill rate, errors, CPM
      // Answers: "Which SSPs are performing and which are failing?"
      // ─────────────────────────────────────────────────────────────────
      case 'bidder_summary': {
        const [requestStats, priceStats] = await Promise.all([
          // Delta-based bidder request counts for the period
          queryAthena<Record<string, string>>(`
            WITH bounds AS (
              SELECT min(timestamp) AS t_start, max(timestamp) AS t_end
              FROM counter
              WHERE name LIKE 'adapter.%.requests.%'
                AND timestamp >= date_add('hour', -${hours}, now())
            ),
            deltas AS (
              SELECT
                regexp_extract(name, 'adapter\\.([^.]+)\\.requests\\.(.+)', 1) AS bidder,
                regexp_extract(name, 'adapter\\.([^.]+)\\.requests\\.(.+)', 2) AS metric,
                max(count) - min(count) AS delta
              FROM counter, bounds
              WHERE name LIKE 'adapter.%.requests.%'
                AND NOT name LIKE '%.type.%'
                AND timestamp IN (bounds.t_start, bounds.t_end)
              GROUP BY 1, 2
            )
            SELECT
              bidder,
              coalesce(sum(CASE WHEN metric='gotbids' THEN delta END), 0) AS gotbids,
              coalesce(sum(CASE WHEN metric='nobid' THEN delta END), 0) AS nobid,
              coalesce(sum(CASE WHEN metric='timeout' THEN delta END), 0) AS timeout,
              coalesce(sum(CASE WHEN metric='badinput' THEN delta END), 0) AS badinput,
              coalesce(sum(CASE WHEN metric='badserverresponse' THEN delta END), 0) AS badresponse,
              coalesce(sum(CASE WHEN metric='unknown_error' THEN delta END), 0) AS unknown_err
            FROM deltas
            GROUP BY bidder
            ORDER BY bidder
          `),
          // Latest CPM per bidder (histogram already aggregated)
          queryAthena<Record<string, string>>(`
            SELECT
              regexp_extract(name, 'adapter\\.([^.]+)\\.prices', 1) AS bidder,
              count AS total_bids,
              round(mean / 100.0, 2) AS avg_cpm,
              round(median / 100.0, 2) AS median_cpm,
              round(min / 100.0, 2) AS min_cpm,
              round(max / 100.0, 2) AS max_cpm,
              round(p95 / 100.0, 2) AS p95_cpm
            FROM histogram
            WHERE name LIKE 'adapter.%.prices'
            ORDER BY timestamp DESC
            LIMIT 10
          `),
        ]);

        // Latest price per bidder (dedup)
        const prices: Record<string, Record<string, string>> = {};
        priceStats.forEach((r) => {
          if (!prices[r.bidder]) prices[r.bidder] = r;
        });

        return NextResponse.json(
          requestStats.map((r) => {
            const gotbids = parseInt(r.gotbids) || 0;
            const nobid = parseInt(r.nobid) || 0;
            const timeout = parseInt(r.timeout) || 0;
            const badinput = parseInt(r.badinput) || 0;
            const badresponse = parseInt(r.badresponse) || 0;
            const unknown = parseInt(r.unknown_err) || 0;
            const total = gotbids + nobid + timeout + badinput + badresponse + unknown;
            const errors = timeout + badinput + badresponse + unknown;
            const p = prices[r.bidder];

            return {
              bidder: r.bidder,
              gotbids,
              nobid,
              timeout,
              errors,
              total,
              fill_rate: total > 0 ? parseFloat((100 * gotbids / total).toFixed(1)) : 0,
              error_rate: total > 0 ? parseFloat((100 * errors / total).toFixed(1)) : 0,
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
            };
          })
        );
      }

      // ─────────────────────────────────────────────────────────────────
      // LATENCY TREND — time-bucketed latency percentiles
      // Answers: "Is latency stable or degrading? When did spikes happen?"
      // Result size: bounded by # of time buckets (max ~48 for hourly/24h)
      // ─────────────────────────────────────────────────────────────────
      case 'latency_trend': {
        const bucket = bucketForHours(hours);
        const rows = await queryAthena<Record<string, string>>(`
          SELECT
            date_trunc('${bucket}', timestamp) AS bucket,
            round(avg(mean), 1) AS mean_ms,
            round(avg(median), 1) AS median_ms,
            round(max(p95), 1) AS p95_ms,
            round(max(p99), 1) AS p99_ms,
            round(max(max), 1) AS max_ms,
            max(count) - min(count) AS requests_in_bucket
          FROM timer
          WHERE name = 'request_time'
            AND timestamp >= date_add('hour', -${hours}, now())
          GROUP BY date_trunc('${bucket}', timestamp)
          ORDER BY bucket
        `);
        return NextResponse.json(
          rows.map((r) => ({
            bucket: r.bucket,
            mean_ms: parseFloat(r.mean_ms),
            median_ms: parseFloat(r.median_ms),
            p95_ms: parseFloat(r.p95_ms),
            p99_ms: parseFloat(r.p99_ms),
            max_ms: parseFloat(r.max_ms),
            requests: parseInt(r.requests_in_bucket) || 0,
          }))
        );
      }

      // ─────────────────────────────────────────────────────────────────
      // VOLUME TREND — time-bucketed request & impression counts
      // Answers: "What's our traffic pattern? Are we growing?"
      // ─────────────────────────────────────────────────────────────────
      case 'volume_trend': {
        const bucket = bucketForHours(hours);
        const rows = await queryAthena<Record<string, string>>(`
          SELECT
            date_trunc('${bucket}', timestamp) AS bucket,
            name,
            max(count) - min(count) AS delta
          FROM counter
          WHERE name IN ('requests.ok.openrtb2-web','requests.ok.openrtb2-app',
                         'imps_banner','imps_requested')
            AND timestamp >= date_add('hour', -${hours}, now())
          GROUP BY date_trunc('${bucket}', timestamp), name
          ORDER BY bucket
        `);

        // Pivot: one row per bucket with all metrics as columns
        const buckets = new Map<string, Record<string, number>>();
        rows.forEach((r) => {
          if (!buckets.has(r.bucket)) buckets.set(r.bucket, {});
          const entry = buckets.get(r.bucket)!;
          const key = r.name.replace('requests.ok.', '').replace('imps_', 'imps_');
          entry[key] = parseInt(r.delta) || 0;
        });

        return NextResponse.json(
          [...buckets.entries()].map(([bucket, metrics]) => ({
            bucket,
            ...metrics,
          }))
        );
      }

      // ─────────────────────────────────────────────────────────────────
      // CPM SNAPSHOT — current price distribution per bidder
      // Answers: "What CPMs are we getting? Who's paying the most?"
      // Result size: exactly 1 row per bidder with price data
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
            round(mean / 100.0, 2) AS avg_cpm,
            round(median / 100.0, 2) AS median_cpm,
            round(min / 100.0, 2) AS min_cpm,
            round(max / 100.0, 2) AS max_cpm,
            round(p75 / 100.0, 2) AS p75_cpm,
            round(p95 / 100.0, 2) AS p95_cpm,
            round(p99 / 100.0, 2) AS p99_cpm,
            round(stddev / 100.0, 2) AS stddev_cpm
          FROM histogram, latest
          WHERE name LIKE 'adapter.%.prices'
            AND timestamp = latest.ts
          ORDER BY mean DESC
        `);
        return NextResponse.json(
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
        );
      }

      // ─────────────────────────────────────────────────────────────────
      // BIDDER DETAIL — everything about one bidder
      // Answers: "Tell me about appnexus — is it healthy? What's its trend?"
      // ─────────────────────────────────────────────────────────────────
      case 'bidder_detail': {
        const bidder = param(url, 'bidder');
        if (!bidder) {
          return NextResponse.json({ error: 'bidder param required' }, { status: 400 });
        }
        const safeBidder = bidder.replace(/'/g, "''");
        const bucket = bucketForHours(hours);

        const [counts, priceTrend] = await Promise.all([
          // Request counts over time for this bidder
          queryAthena<Record<string, string>>(`
            SELECT
              date_trunc('${bucket}', timestamp) AS bucket,
              regexp_extract(name, 'adapter\\.${safeBidder}\\.requests\\.(.+)', 1) AS metric,
              max(count) - min(count) AS delta
            FROM counter
            WHERE name LIKE 'adapter.${safeBidder}.requests.%'
              AND NOT name LIKE '%.type.%'
              AND timestamp >= date_add('hour', -${hours}, now())
            GROUP BY 1, 2
            ORDER BY bucket
          `),
          // Price trend for this bidder
          queryAthena<Record<string, string>>(`
            SELECT
              date_trunc('${bucket}', timestamp) AS bucket,
              round(avg(mean) / 100.0, 2) AS avg_cpm,
              round(max(max) / 100.0, 2) AS max_cpm,
              max(count) - min(count) AS bids_delta
            FROM histogram
            WHERE name = 'adapter.${safeBidder}.prices'
              AND timestamp >= date_add('hour', -${hours}, now())
            GROUP BY 1
            ORDER BY bucket
          `),
        ]);

        // Pivot counts by bucket
        const bucketMap = new Map<string, Record<string, number>>();
        counts.forEach((r) => {
          if (!bucketMap.has(r.bucket)) bucketMap.set(r.bucket, {});
          bucketMap.get(r.bucket)![r.metric] = parseInt(r.delta) || 0;
        });

        return NextResponse.json({
          bidder,
          period_hours: hours,
          request_trend: [...bucketMap.entries()].map(([bucket, metrics]) => ({
            bucket,
            ...metrics,
          })),
          price_trend: priceTrend.map((r) => ({
            bucket: r.bucket,
            avg_cpm: parseFloat(r.avg_cpm),
            max_cpm: parseFloat(r.max_cpm),
            bids: parseInt(r.bids_delta) || 0,
          })),
        });
      }

      default:
        return NextResponse.json({ error: `Unknown type: ${type}` }, { status: 400 });
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    console.error('[Athena] Query error:', message);
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
