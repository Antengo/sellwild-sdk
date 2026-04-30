'use client';

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  LineChart,
  Line,
  Cell,
  Legend,
  Area,
  AreaChart,
} from 'recharts';
import type {
  BidderSummary,
  LatencyBucket,
  VolumeBucket,
  CpmSnapshot,
} from '@/lib/athena-types';

const COLORS = [
  '#10b981', '#3b82f6', '#f59e0b', '#ef4444', '#8b5cf6',
  '#ec4899', '#06b6d4', '#84cc16',
];

const tooltipStyle = {
  contentStyle: {
    backgroundColor: '#1f2937',
    border: '1px solid #374151',
    borderRadius: '8px',
    fontSize: '12px',
    color: '#e5e7eb',
  },
  labelStyle: { color: '#9ca3af' },
};

function ChartCard({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl border border-gray-800 bg-gray-900 p-5">
      <div className="mb-4">
        <h3 className="font-semibold">{title}</h3>
        {subtitle && <p className="text-xs text-gray-500 mt-1">{subtitle}</p>}
      </div>
      {children}
    </div>
  );
}

function fmtTime(ts: string): string {
  const d = new Date(ts);
  return d.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

/** ─── Latency trend (line chart with percentile bands) ────────────── */
export function LatencyTrendChart({ data }: { data: LatencyBucket[] }) {
  const formatted = data.map((d) => ({ ...d, time: fmtTime(d.bucket) }));
  return (
    <ChartCard title="Auction Latency" subtitle="Percentiles over time">
      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={formatted}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
          <XAxis dataKey="time" stroke="#6b7280" tick={{ fontSize: 10 }} />
          <YAxis stroke="#6b7280" tick={{ fontSize: 11 }} unit="ms" />
          <Tooltip {...tooltipStyle} formatter={(v: number) => [`${v}ms`]} />
          <Legend />
          <Line type="monotone" dataKey="mean_ms" name="Mean" stroke="#10b981" strokeWidth={2} dot={false} />
          <Line type="monotone" dataKey="median_ms" name="Median" stroke="#3b82f6" strokeWidth={2} dot={false} />
          <Line type="monotone" dataKey="p95_ms" name="p95" stroke="#f59e0b" strokeWidth={1.5} strokeDasharray="4 2" dot={false} />
          <Line type="monotone" dataKey="p99_ms" name="p99" stroke="#ef4444" strokeWidth={1.5} strokeDasharray="4 2" dot={false} />
        </LineChart>
      </ResponsiveContainer>
    </ChartCard>
  );
}

/** ─── Volume trend (area chart) ───────────────────────────────────── */
export function VolumeTrendChart({ data }: { data: VolumeBucket[] }) {
  const formatted = data.map((d) => ({ ...d, time: fmtTime(d.bucket) }));
  return (
    <ChartCard title="Traffic Volume" subtitle="Requests and impressions per period">
      <ResponsiveContainer width="100%" height={280}>
        <AreaChart data={formatted}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
          <XAxis dataKey="time" stroke="#6b7280" tick={{ fontSize: 10 }} />
          <YAxis stroke="#6b7280" tick={{ fontSize: 11 }} />
          <Tooltip {...tooltipStyle} />
          <Legend />
          <Area type="monotone" dataKey="openrtb2-web" name="Web Requests" stroke="#3b82f6" fill="#3b82f620" strokeWidth={2} />
          <Area type="monotone" dataKey="openrtb2-app" name="App Requests" stroke="#10b981" fill="#10b98120" strokeWidth={2} />
          <Area type="monotone" dataKey="imps_banner" name="Banner Imps" stroke="#f59e0b" fill="#f59e0b20" strokeWidth={1.5} />
        </AreaChart>
      </ResponsiveContainer>
    </ChartCard>
  );
}

/** ─── CPM snapshot (horizontal bar) ───────────────────────────────── */
export function CpmSnapshotChart({ data }: { data: CpmSnapshot[] }) {
  return (
    <ChartCard title="CPM by SSP" subtitle="Current bid price distribution">
      <ResponsiveContainer width="100%" height={Math.max(180, data.length * 55)}>
        <BarChart data={data} layout="vertical" margin={{ left: 30, right: 20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
          <XAxis type="number" stroke="#6b7280" tick={{ fontSize: 11 }} />
          <YAxis dataKey="bidder" type="category" stroke="#6b7280" width={100} tick={{ fontSize: 12 }} />
          <Tooltip {...tooltipStyle} formatter={(v: number, name: string) => [`$${v.toFixed(2)}`, name]} />
          <Legend />
          <Bar dataKey="avg_cpm" name="Avg CPM" radius={[0, 4, 4, 0]}>
            {data.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
          </Bar>
          <Bar dataKey="max_cpm" name="Max CPM" fill="#374151" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </ChartCard>
  );
}

/** ─── Bidder fill/error stacked bar ───────────────────────────────── */
export function BidderBreakdownChart({ data }: { data: BidderSummary[] }) {
  return (
    <ChartCard title="Bidder Breakdown" subtitle="Bids, no-bids, and errors per SSP">
      <ResponsiveContainer width="100%" height={Math.max(200, data.length * 50)}>
        <BarChart data={data} layout="vertical" margin={{ left: 30, right: 20 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
          <XAxis type="number" stroke="#6b7280" tick={{ fontSize: 11 }} />
          <YAxis dataKey="bidder" type="category" stroke="#6b7280" width={100} tick={{ fontSize: 12 }} />
          <Tooltip {...tooltipStyle} />
          <Legend />
          <Bar dataKey="gotbids" name="Got Bids" stackId="a" fill="#10b981" />
          <Bar dataKey="nobid" name="No Bid" stackId="a" fill="#6b7280" />
          <Bar dataKey="timeout" name="Timeout" stackId="a" fill="#f59e0b" />
          <Bar dataKey="errors" name="Errors" stackId="a" fill="#ef4444" />
        </BarChart>
      </ResponsiveContainer>
    </ChartCard>
  );
}

/** ─── Bidder summary table ────────────────────────────────────────── */
export function BidderSummaryTable({ data }: { data: BidderSummary[] }) {
  return (
    <ChartCard title="SSP Performance" subtitle="Fill rate, error rate, and CPM per bidder">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-800 text-gray-500 text-xs uppercase tracking-wider">
              <th className="text-left px-4 py-2">Bidder</th>
              <th className="text-right px-4 py-2">Bids</th>
              <th className="text-right px-4 py-2">No Bid</th>
              <th className="text-right px-4 py-2">Fill Rate</th>
              <th className="text-right px-4 py-2">Errors</th>
              <th className="text-right px-4 py-2">Avg CPM</th>
              <th className="text-right px-4 py-2">Max CPM</th>
            </tr>
          </thead>
          <tbody>
            {data.map((b) => (
              <tr key={b.bidder} className="border-b border-gray-800/50 hover:bg-gray-800/30">
                <td className="px-4 py-3 font-medium">{b.bidder}</td>
                <td className="px-4 py-3 text-right font-mono text-emerald-400">{b.gotbids}</td>
                <td className="px-4 py-3 text-right font-mono text-gray-500">{b.nobid}</td>
                <td className="px-4 py-3 text-right">
                  <span className={`font-mono font-bold ${
                    b.fill_rate >= 50 ? 'text-emerald-400' : b.fill_rate >= 20 ? 'text-amber-400' : 'text-red-400'
                  }`}>
                    {b.fill_rate}%
                  </span>
                </td>
                <td className="px-4 py-3 text-right font-mono text-red-400">
                  {b.errors > 0 ? b.errors : <span className="text-gray-600">0</span>}
                </td>
                <td className="px-4 py-3 text-right font-mono">
                  {b.cpm ? `$${b.cpm.avg.toFixed(2)}` : '—'}
                </td>
                <td className="px-4 py-3 text-right font-mono">
                  {b.cpm ? `$${b.cpm.max.toFixed(2)}` : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </ChartCard>
  );
}
