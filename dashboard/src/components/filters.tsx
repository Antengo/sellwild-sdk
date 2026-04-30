'use client';

import type { AuctionQueryFilters } from '@/lib/athena-types';

const TIME_RANGES = [
  { label: 'Last 1 Hour', hours: 1 },
  { label: 'Last 6 Hours', hours: 6 },
  { label: 'Last 24 Hours', hours: 24 },
  { label: 'All Data', hours: 0 },
];

interface FiltersProps {
  filters: AuctionQueryFilters;
  onChange: (filters: AuctionQueryFilters) => void;
  autoRefresh?: boolean;
  onAutoRefreshChange?: (enabled: boolean) => void;
  onRefresh?: () => void;
  loading?: boolean;
}

const inputClass =
  'bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white focus:border-emerald-500 focus:ring-1 focus:ring-emerald-500 outline-none';

export function Filters({
  filters,
  onChange,
  autoRefresh,
  onAutoRefreshChange,
  onRefresh,
  loading,
}: FiltersProps) {
  return (
    <div className="flex flex-wrap items-center gap-3">
      <select
        value={filters.hours || 0}
        onChange={(e) => onChange({ ...filters, hours: parseInt(e.target.value) || undefined })}
        className={inputClass}
      >
        {TIME_RANGES.map((r) => (
          <option key={r.hours} value={r.hours}>
            {r.label}
          </option>
        ))}
      </select>

      {onRefresh && (
        <button
          onClick={onRefresh}
          disabled={loading}
          className="px-3 py-2 rounded-lg text-sm font-medium bg-gray-800 border border-gray-700 text-gray-300 hover:border-gray-600 hover:text-white transition-colors disabled:opacity-50"
        >
          {loading ? 'Loading...' : 'Refresh'}
        </button>
      )}

      {onAutoRefreshChange && (
        <button
          onClick={() => onAutoRefreshChange(!autoRefresh)}
          className={`ml-auto px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
            autoRefresh
              ? 'bg-emerald-600 text-white'
              : 'bg-gray-800 text-gray-400 border border-gray-700 hover:border-gray-600'
          }`}
        >
          {autoRefresh ? 'Auto-refresh ON (30s)' : 'Auto-refresh'}
        </button>
      )}
    </div>
  );
}
