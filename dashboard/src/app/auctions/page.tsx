'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';

interface Auction {
  id: string;
  timestamp: string;
  cur: string;
  source: string;
  seatbid: Array<{ seat?: string; bid: Array<{ price?: number }> }>;
  ext: {
    responsetimemillis?: Record<string, number>;
    errors?: Record<string, unknown[]>;
    tmaxrequest?: number;
  };
}

export default function AuctionFeedPage() {
  const [auctions, setAuctions] = useState<Auction[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/logs?type=recent&hours=24')
      .then((r) => r.json())
      .then((data) => {
        if (data.error) throw new Error(data.error);
        setAuctions(data);
      })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Auction Feed</h1>
        <p className="text-sm text-gray-500 mt-1">
          Live auctions from Prebid Server &middot; Click any row to inspect
        </p>
      </div>

      {error && (
        <div className="rounded-xl border border-red-800 bg-red-900/20 p-4 text-red-400 text-sm">
          {error}
        </div>
      )}

      {loading ? (
        <div className="text-center py-20 text-gray-500">
          <div className="w-8 h-8 border-2 border-emerald-500 border-t-transparent rounded-full animate-spin mx-auto mb-4" />
          Querying CloudWatch Logs...
        </div>
      ) : (
        <div className="rounded-xl border border-gray-800 bg-gray-900 overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wider">
                <th className="text-left px-5 py-3">Auction ID</th>
                <th className="text-left px-5 py-3">Source</th>
                <th className="text-left px-5 py-3">Time</th>
                <th className="text-left px-5 py-3">Bidders</th>
                <th className="text-left px-5 py-3">Winner</th>
                <th className="text-right px-5 py-3">CPM</th>
                <th className="text-right px-5 py-3">Latency</th>
              </tr>
            </thead>
            <tbody>
              {auctions.map((a) => {
                const bidders = Object.keys(a.ext?.responsetimemillis || {});
                const maxLatency = Math.max(...Object.values(a.ext?.responsetimemillis || {}), 0);
                const totalBids = a.seatbid.reduce((sum, sb) => sum + sb.bid.length, 0);
                const errorCount = Object.keys(a.ext?.errors || {}).length;

                const winnerSeat = a.seatbid.find(sb => sb.bid.length > 0);
                const winnerCpm = winnerSeat?.bid[0]?.price;

                return (
                  <tr key={a.id} className={`border-b border-gray-800/50 hover:bg-gray-800/50 transition-colors ${totalBids > 0 ? 'bg-emerald-900/5' : ''}`}>
                    <td className="px-5 py-3">
                      <Link
                        href={`/auctions/${a.id}`}
                        className="font-mono text-xs text-emerald-400 hover:text-emerald-300"
                      >
                        {a.id}
                      </Link>
                    </td>
                    <td className="px-5 py-3">
                      <span className={`px-2 py-0.5 rounded text-[11px] font-medium ${
                        a.source.includes('WeatherBug') || a.source === 'Demo App'
                          ? 'bg-blue-900/50 text-blue-400'
                          : 'bg-gray-800 text-gray-500'
                      }`}>
                        {a.source}
                      </span>
                    </td>
                    <td className="px-5 py-3 text-gray-400">
                      {new Date(a.timestamp).toLocaleTimeString()}
                    </td>
                    <td className="px-5 py-3">
                      <div className="flex flex-wrap gap-1">
                        {bidders.map((b) => (
                          <span
                            key={b}
                            className="px-1.5 py-0.5 rounded bg-gray-800 text-[11px] font-mono"
                          >
                            {b}
                          </span>
                        ))}
                      </div>
                    </td>
                    <td className="px-5 py-3 font-medium">
                      {winnerSeat ? (
                        <span className="text-emerald-400">{winnerSeat.seat}</span>
                      ) : (
                        <span className="text-gray-600">—</span>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right font-mono">
                      {winnerCpm ? (
                        <span className="text-emerald-400 font-bold">${winnerCpm.toFixed(2)}</span>
                      ) : (
                        <span className="text-gray-600">—</span>
                      )}
                    </td>
                    <td className="px-5 py-3 text-right font-mono">
                      <span
                        className={
                          maxLatency > 1000
                            ? 'text-red-400'
                            : maxLatency > 500
                              ? 'text-amber-400'
                              : 'text-emerald-400'
                        }
                      >
                        {maxLatency}ms
                      </span>
                    </td>
                  </tr>
                );
              })}
              {auctions.length === 0 && (
                <tr>
                  <td colSpan={7} className="px-5 py-12 text-center text-gray-600">
                    No auctions found in the last 24 hours
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
