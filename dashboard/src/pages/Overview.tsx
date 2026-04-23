import { useAuctionDashboard } from '@/lib/use-auction-data'
import { StatsCard } from '@/components/stats-card'
import { Filters } from '@/components/filters'
import {
  LatencyTrendChart,
  VolumeTrendChart,
  CpmSnapshotChart,
  BidderBreakdownChart,
  BidderSummaryTable,
} from '@/components/charts'

export default function OverviewPage() {
  const {
    filters, setFilters,
    loading, error,
    autoRefresh, setAutoRefresh,
    overview, bidderSummary, latencyTrend, volumeTrend, cpmSnapshot,
    refresh,
  } = useAuctionDashboard({ hours: 24 })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Auction Overview</h1>
        <p className="text-sm text-gray-500 mt-1">
          Prebid Server metrics &middot; prebid.sellwild.com &middot; AWS Athena
        </p>
      </div>

      <Filters
        filters={filters}
        onChange={setFilters}
        autoRefresh={autoRefresh}
        onAutoRefreshChange={setAutoRefresh}
        onRefresh={refresh}
        loading={loading}
      />

      {error && (
        <div className="rounded-xl border border-red-800 bg-red-900/20 p-4 text-red-400 text-sm whitespace-pre-wrap">
          {error}
        </div>
      )}

      {loading && !overview && (
        <div className="text-center py-20 text-gray-500">
          <div className="w-8 h-8 border-2 border-emerald-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          Querying Athena...
        </div>
      )}

      {overview && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
            <StatsCard
              label="Auctions (period)"
              value={overview.auctions_in_period.toLocaleString()}
              detail={`${overview.total_auctions_lifetime.toLocaleString()} lifetime`}
              color="blue"
            />
            <StatsCard
              label="Avg Latency"
              value={`${overview.latency.mean_ms}ms`}
              detail={`p75 ${overview.latency.median_ms}ms`}
              color={overview.latency.mean_ms <= 200 ? 'emerald' : 'amber'}
            />
            <StatsCard
              label="p95 Latency"
              value={`${overview.latency.p95_ms}ms`}
              detail={`p99: ${overview.latency.p99_ms}ms`}
              color={overview.latency.p95_ms <= 500 ? 'emerald' : 'amber'}
            />
            <StatsCard
              label="Banner Imps"
              value={overview.impressions.banner.toLocaleString()}
              detail={`${overview.impressions.requested.toLocaleString()} requested`}
              color="emerald"
            />
            <StatsCard
              label="Active SSPs"
              value={overview.active_bidders}
              color="purple"
            />
            <StatsCard
              label="Req/sec"
              value={overview.requests_per_sec}
              detail={`${overview.requests.web} web / ${overview.requests.app} app`}
              color="blue"
            />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <LatencyTrendChart data={latencyTrend} />
            <VolumeTrendChart data={volumeTrend} />
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <CpmSnapshotChart data={cpmSnapshot} />
            <BidderBreakdownChart data={bidderSummary} />
          </div>

          <BidderSummaryTable data={bidderSummary} />
        </>
      )}
    </div>
  )
}
