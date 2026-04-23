import { useParams, Link } from 'react-router-dom'
import { useState, useEffect } from 'react'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts'

const tooltipStyle = {
  contentStyle: {
    backgroundColor: '#1f2937',
    border: '1px solid #374151',
    borderRadius: '8px',
    fontSize: '12px',
    color: '#e5e7eb',
  },
}

interface Bid {
  id?: string
  impid?: string
  price?: number
  w?: number
  h?: number
  ext?: {
    prebid?: { type?: string; meta?: { adaptercode?: string } }
    origbidcpm?: number
    origbidcur?: string
  }
}

interface AuctionDetailData {
  id: string
  timestamp: string
  cur: string
  source: string
  seatbid: Array<{ seat?: string; bid: Bid[] }>
  ext: {
    responsetimemillis?: Record<string, number>
    errors?: Record<string, Array<{ code: number; message: string }>>
    tmaxrequest?: number
    prebid?: { auctiontimestamp?: number }
    debug?: {
      resolvedrequest?: {
        imp?: Array<{
          id: string
          banner?: { format?: Array<{ w: number; h: number }> }
          video?: { w?: number; h?: number }
        }>
      }
    }
  }
}

interface SlotData {
  impid: string
  size: string
  bidders: { bidder: string; ms: number; bid: Bid | null; error?: string }[]
  winner: { bidder: string; cpm: number; type?: string } | null
}

export default function AuctionDetailPage() {
  const { auctionId } = useParams<{ auctionId: string }>()
  const [auction, setAuction] = useState<AuctionDetailData | null>(null)
  const [loading, setLoading] = useState(true)
  const [attempt, setAttempt] = useState(0)

  useEffect(() => {
    let cancelled = false
    const maxAttempts = 10
    const delayMs = 3000

    async function poll(n: number) {
      if (cancelled) return
      setLoading(true)
      try {
        const res = await fetch(
          `/.netlify/functions/logs?type=detail&auctionId=${encodeURIComponent(auctionId!)}&hours=72`
        )
        const data = await res.json()
        if (!data.error && data.id) {
          if (!cancelled) setAuction(data)
          if (!cancelled) setLoading(false)
          return
        }
      } catch { /* retry */ }

      if (n < maxAttempts && !cancelled) {
        setAttempt(n + 1)
        setTimeout(() => poll(n + 1), delayMs)
      } else if (!cancelled) {
        setLoading(false)
      }
    }

    poll(0)
    return () => { cancelled = true }
  }, [auctionId])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="text-center">
          <div className="w-8 h-8 border-2 border-emerald-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          <p className="text-white font-mono text-sm mb-2">{auctionId}</p>
          <p className="text-gray-500 text-sm">
            {attempt === 0
              ? 'Querying CloudWatch Logs...'
              : `Waiting for auction to appear... (attempt ${attempt + 1}/10)`}
          </p>
          <p className="text-gray-600 text-xs mt-2">PBS logs take a few seconds to reach CloudWatch</p>
        </div>
      </div>
    )
  }

  if (!auction) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <div className="rounded-xl border border-amber-800 bg-amber-900/20 p-8 text-center max-w-md">
          <p className="text-amber-400 font-semibold text-lg mb-2">Auction Not Found Yet</p>
          <p className="text-gray-500 text-sm mb-1">The auction log hasn{"'"}t arrived in CloudWatch yet.</p>
          <p className="text-gray-600 font-mono text-xs mb-4">{auctionId}</p>
          <button
            onClick={() => { setAttempt(0); setLoading(true) }}
            className="px-4 py-2 bg-amber-600 hover:bg-amber-500 text-white rounded-lg text-sm font-medium transition-colors mr-3"
          >
            Try Again
          </button>
          <Link to="/auctions" className="text-emerald-400 hover:text-emerald-300 text-sm">
            Back to Auction Feed
          </Link>
        </div>
      </div>
    )
  }

  // Build per-slot data
  const bidders = Object.entries(auction.ext?.responsetimemillis || {})
  const errors = auction.ext?.errors || {}
  const tmax = auction.ext?.tmaxrequest || 0

  const imps = auction.ext?.debug?.resolvedrequest?.imp || []

  const allBids = auction.seatbid.flatMap((sb) =>
    sb.bid.map((b) => ({ ...b, seat: sb.seat || 'unknown' }))
  )

  const slotIds = imps.length > 0
    ? imps.map((imp) => imp.id)
    : [...new Set(allBids.map((b) => b.impid).filter(Boolean))] as string[]

  const slots: SlotData[] = slotIds.length > 0
    ? slotIds.map((impid) => {
        const imp = imps.find((i) => i.id === impid)
        const fmt = imp?.banner?.format?.[0]
        const size = fmt ? `${fmt.w}x${fmt.h}` : imp?.video ? `${imp.video.w}x${imp.video.h}` : '?'

        const slotBids = allBids.filter((b) => b.impid === impid)
        const winner = slotBids.length > 0
          ? slotBids.sort((a, b) => (b.price || 0) - (a.price || 0))[0]
          : null

        return {
          impid,
          size,
          bidders: bidders.map(([bidder, ms]) => ({
            bidder,
            ms,
            bid: slotBids.find((b) => b.seat === bidder) || null,
            error: errors[bidder]?.[0]?.message,
          })),
          winner: winner
            ? {
                bidder: winner.seat,
                cpm: winner.price || 0,
                type: winner.ext?.prebid?.type,
              }
            : null,
        }
      })
    : [{
        impid: 'all',
        size: '',
        bidders: bidders.map(([bidder, ms]) => {
          const bid = allBids.find((b) => b.seat === bidder)
          return { bidder, ms, bid: bid || null, error: errors[bidder]?.[0]?.message }
        }),
        winner: allBids.length > 0
          ? { bidder: allBids[0]!.seat, cpm: allBids[0]!.price || 0 }
          : null,
      }]

  const totalFilled = slots.filter((s) => s.winner).length
  const totalRevenue = slots.reduce((sum, s) => sum + (s.winner?.cpm || 0), 0)
  const maxLatency = Math.max(...bidders.map(([, ms]) => ms), 0)

  return (
    <div className="space-y-6">
      <Link to="/auctions" className="text-sm text-gray-500 hover:text-gray-300 transition-colors">
        &larr; Back to Auction Feed
      </Link>

      {/* Header */}
      <div className="flex items-start justify-between flex-wrap gap-4">
        <div>
          <h1 className="text-2xl font-bold flex items-center gap-3">
            Auction Detail
            {totalFilled > 0 ? (
              <span className="px-2.5 py-1 rounded-full bg-emerald-900/50 text-emerald-400 text-xs font-medium">
                {totalFilled}/{slots.length} FILLED
              </span>
            ) : (
              <span className="px-2.5 py-1 rounded-full bg-amber-900/50 text-amber-400 text-xs font-medium">
                NO FILL
              </span>
            )}
          </h1>
          <div className="flex items-center gap-3 mt-1">
            <p className="text-sm text-gray-500 font-mono select-all">{auction.id}</p>
            <span className={`px-2 py-0.5 rounded text-[11px] font-medium ${
              auction.source?.includes('WeatherBug') || auction.source === 'Demo App'
                ? 'bg-blue-900/50 text-blue-400'
                : 'bg-gray-800 text-gray-500'
            }`}>
              {auction.source || 'Unknown'}
            </span>
          </div>
        </div>
        <div className="text-right text-sm text-gray-400">
          <p>{new Date(auction.timestamp).toLocaleString()}</p>
          <p className="font-mono">{auction.cur} &middot; tmax {tmax}ms</p>
        </div>
      </div>

      {/* Summary KPIs */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
        <Metric label="Ad Slots" value={slots.length} />
        <Metric label="Filled" value={totalFilled} highlight={totalFilled > 0} />
        <Metric label="Total CPM" value={`$${totalRevenue.toFixed(2)}`} highlight={totalRevenue > 0} />
        <Metric label="Fill Rate" value={`${slots.length > 0 ? Math.round((totalFilled / slots.length) * 100) : 0}%`} highlight={totalFilled > 0} />
        <Metric label="Max Latency" value={`${maxLatency}ms`} warn={maxLatency > 500} />
      </div>

      {/* Per-Slot Breakdown */}
      {slots.map((slot) => (
        <div key={slot.impid} className="rounded-xl border border-gray-800 bg-gray-900 overflow-hidden">
          <div className="px-5 py-4 border-b border-gray-800 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <span className="text-lg font-bold font-mono">{slot.size || slot.impid}</span>
              <span className="text-xs text-gray-500 font-mono">{slot.impid}</span>
            </div>
            {slot.winner ? (
              <span className="text-emerald-400 font-mono font-bold">${slot.winner.cpm.toFixed(2)}</span>
            ) : (
              <span className="text-gray-600 text-sm">no fill</span>
            )}
          </div>

          <table className="w-full text-sm">
            <tbody>
              {slot.bidders.map(({ bidder, ms, bid, error }) => (
                <tr key={bidder} className={`border-b border-gray-800/30 ${bid ? 'bg-emerald-900/5' : ''}`}>
                  <td className="px-5 py-3 w-8">
                    {bid ? (
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-emerald-500" />
                    ) : error ? (
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-red-500" />
                    ) : (
                      <span className="inline-block w-2.5 h-2.5 rounded-full bg-gray-600" />
                    )}
                  </td>
                  <td className="py-3 font-medium w-36">{bidder}</td>
                  <td className="py-3 text-right font-mono text-gray-400 w-20">{ms}ms</td>
                  <td className="px-5 py-3 text-right font-mono w-24">
                    {bid?.price ? (
                      <span className="text-emerald-400 font-bold">${bid.price.toFixed(2)}</span>
                    ) : error ? (
                      <span className="text-red-400 text-xs">error</span>
                    ) : (
                      <span className="text-gray-600">no bid</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          {slot.winner && (
            <div className="mx-5 mb-4 mt-2 rounded-lg bg-emerald-900/20 border border-emerald-800/50 px-4 py-3">
              <p className="text-emerald-400 font-semibold text-sm">
                Winner: {slot.winner.bidder}
              </p>
              <p className="text-emerald-600 text-xs">
                ${slot.winner.cpm.toFixed(2)} CPM
                {slot.winner.type ? ` \u2014 ${slot.size} ${slot.winner.type}` : ''}
              </p>
            </div>
          )}
        </div>
      ))}

      {/* Response Time Chart */}
      {bidders.length > 0 && (
        <div className="rounded-xl border border-gray-800 bg-gray-900 p-5">
          <h3 className="font-semibold mb-4">Response Time per Bidder</h3>
          <ResponsiveContainer width="100%" height={Math.max(160, bidders.length * 45)}>
            <BarChart
              data={bidders.map(([bidder, ms]) => ({
                bidder,
                response_ms: ms,
                hasBid: allBids.some((b) => b.seat === bidder),
                hasError: !!errors[bidder],
              }))}
              layout="vertical"
              margin={{ left: 30, right: 20 }}
            >
              <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
              <XAxis type="number" stroke="#6b7280" tick={{ fontSize: 11 }} unit="ms" />
              <YAxis dataKey="bidder" type="category" stroke="#6b7280" width={110} tick={{ fontSize: 12 }} />
              <Tooltip {...tooltipStyle} formatter={(v: number) => [`${v}ms`, 'Latency']} />
              <Bar dataKey="response_ms" radius={[0, 6, 6, 0]}>
                {bidders.map(([bidder], i) => {
                  const hasBid = allBids.some((b) => b.seat === bidder)
                  const hasError = !!errors[bidder]
                  return (
                    <Cell
                      key={i}
                      fill={hasError ? '#ef4444' : hasBid ? '#10b981' : '#3b82f6'}
                    />
                  )
                })}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
          {tmax > 0 && <p className="text-xs text-gray-600 mt-2">tmax: {tmax}ms</p>}
        </div>
      )}

      {/* Raw JSON */}
      <details className="rounded-xl border border-gray-800 bg-gray-900">
        <summary className="px-5 py-4 cursor-pointer text-sm text-gray-400 hover:text-white transition-colors">
          Raw OpenRTB Response
        </summary>
        <pre className="px-5 pb-5 text-xs text-gray-500 overflow-x-auto font-mono">
          {JSON.stringify(auction, null, 2)}
        </pre>
      </details>
    </div>
  )
}

function Metric({ label, value, highlight, warn }: {
  label: string
  value: string | number
  highlight?: boolean
  warn?: boolean
}) {
  return (
    <div className={`rounded-xl border p-4 ${
      highlight ? 'border-emerald-500/30 bg-emerald-500/5' :
      warn ? 'border-red-500/30 bg-red-500/5' :
      'border-gray-800 bg-gray-900'
    }`}>
      <p className="text-xs text-gray-500 mb-1">{label}</p>
      <p className={`text-2xl font-bold ${
        highlight ? 'text-emerald-400' : warn ? 'text-red-400' : 'text-white'
      }`}>
        {value}
      </p>
    </div>
  )
}
